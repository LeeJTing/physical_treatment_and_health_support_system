"""Deterministic report diagrams from the reviewed application workflows.

Run with the bundled Codex Python runtime. Pillow uses Windows Arial fonts.
Diagrams are documentation; no device or backend state is accessed.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import math, textwrap

OUT=Path(__file__).parent/'figures'
OUT.mkdir(exist_ok=True)
FONT=Path(r'C:\Windows\Fonts\arial.ttf')
BOLD=Path(r'C:\Windows\Fonts\arialbd.ttf')
def font(n=26,bold=False): return ImageFont.truetype(str(BOLD if bold else FONT),n)
def canvas(w,h):
    im=Image.new('RGB',(w,h),'white');return im,ImageDraw.Draw(im)
def wrapped(draw,text,width,size=26,bold=False):
    lines=[]
    for paragraph in text.split('\n'):
        line=''
        for word in paragraph.split():
            trial=(line+' '+word).strip()
            if draw.textlength(trial,font=font(size,bold))>width and line:
                lines.append(line);line=word
            else:line=trial
        lines.append(line)
    return lines
def label(draw,box,text,size=26,bold=False,align='center'):
    x0,y0,x1,y1=box
    lines=wrapped(draw,text,x1-x0-22,size,bold)
    height=len(lines)*(size+7)
    assert height<=y1-y0-8,(text,box,height)
    y=y0+(y1-y0-height)/2
    for line in lines:
        w=draw.textlength(line,font=font(size,bold))
        x=(x0+x1-w)/2 if align=='center' else x0+13
        draw.text((x,y),line,font=font(size,bold),fill='#151515');y+=size+7
def box(draw,rect,text,size=26,bold=False,fill='#F5F6F7',radius=12):
    draw.rounded_rectangle(rect,radius=radius,fill=fill,outline='#343A40',width=3)
    label(draw,rect,text,size,bold)
def arrow(draw,points,dashed=False):
    if dashed:
        for a,b in zip(points,points[1:]):
            dist=math.dist(a,b);count=max(1,int(dist/15))
            for i in range(0,count,2):
                j=min(i+1,count)
                draw.line([(a[0]+(b[0]-a[0])*i/count,a[1]+(b[1]-a[1])*i/count),(a[0]+(b[0]-a[0])*j/count,a[1]+(b[1]-a[1])*j/count)],fill='#41474C',width=3)
    else:draw.line(points,fill='#343A40',width=3)
    a,b=points[-2:];angle=math.atan2(b[1]-a[1],b[0]-a[0]);r=14
    draw.polygon([b,(b[0]-r*math.cos(angle-.4),b[1]-r*math.sin(angle-.4)),(b[0]-r*math.cos(angle+.4),b[1]-r*math.sin(angle+.4))],fill='#343A40')
def save(im,name):
    im.save(OUT/(name+'.png'),dpi=(220,220))

def flow(name,title,steps):
    w=1360;h=160+len(steps)*155
    im,dr=canvas(w,h+35);label(dr,(20,5,w-20,65),title,31,True)
    dr.ellipse((467,78,493,104),fill='#20262B')
    previous=(480,104)
    for i,step in enumerate(steps):
        y=135+i*155
        text,decision=(step,False) if isinstance(step,str) else (step[0],True)
        arrow(dr,[previous,(480,y)])
        if decision:
            dr.polygon([(480,y),(885,y+57),(480,y+114),(75,y+57)],fill='#FAFAFA',outline='#343A40',width=3)
            label(dr,(230,y+20,730,y+94),text,25,True)
            arrow(dr,[(885,y+57),(955,y+57)])
            dr.text((900,y+23),'No',font=font(23),fill='#151515')
            box(dr,(960,y-1,1335,y+116),step[1],23,False,'#F5F6F7')
            arrow(dr,[(1145,y+116),(1145,y+128)])
            dr.ellipse((1133,y+129,1157,y+153),outline='#343A40',width=2)
            dr.ellipse((1139,y+135,1151,y+147),fill='#343A40')
            dr.text((494,y+116),'Yes',font=font(22),fill='#151515')
            previous=(480,y+114)
        else:
            box(dr,(75,y,885,y+108),text,27)
            previous=(480,y+108)
    arrow(dr,[previous,(480,h-24)])
    dr.ellipse((464,h-23,496,h+9),outline='#20262B',width=3)
    dr.ellipse((472,h-15,488,h+1),fill='#20262B')
    # Margin below the final node is reserved in the output image.
    save(im,name)

FLOWS={
 'auth_register':('UC100 Register and pass the current entry gates',[
  'Enter username, email, password and confirmation; validate fields','Request account creation and six-digit verification email',('Verification accepted by authentication service?','Keep verification entry; correct or resend code'),
  'Complete provider-account setup when the entry requires it',('Current Terms/Privacy acceptance required?','Continue to the appropriate Profile / Home route'),
  'Read current terms; enter age/guardian and health-data consent',('Required declarations accepted and valid?','Decline / correct; no personalised access'),
  'Save the versioned acceptance; keep form on a write failure','Continue to mandatory Profile setup or Home']),
 'auth_login':('UC200 Authenticate then check required terms and profile',[
  'Restore a usable session or submit valid email/password',('Authentication and required verification/setup complete?','Explain login/provider/code/lockout state; allow retry'),
  'Resolve the signed-in account and current entry requirements',('Current Terms/Privacy acceptance required?','Continue to the appropriate Profile / Home route'),
  'Review current version, explicit consent and age declaration',('Patient accepts valid required declarations?','Decline and end personalised entry'),
  'Save acceptance; retain the form if persistence fails','Route to Profile or Home; restore account reminder scheduling']),
 'auth_google':('UC100 and UC200 Continue with Google',[
  'Check that the configured authentication provider is available','Open the browser sign-in and receive the authenticated callback',('A usable provider session is returned?','Explain unavailable/cancelled entry; keep login usable'),
  'Complete username/password setup only when this account requires it',('New/current Terms acceptance is needed?','Continue to the appropriate Profile / Home route'),
  'Collect valid versioned consent; declining ends personalised entry','Save acceptance, then route by profile completeness']),
 'auth_verify':('UC100 and UC200 Verify email before personalisation',[
  'Enter the emailed six-digit code or request an allowed resend',('Authentication service accepts the code?','Explain incorrect/expired/attempt state; retain entry'),
  'Resolve the verified account and any remaining setup',('Current terms/age declarations require review?','Continue to the appropriate Profile / Home route'),
  'Review and save valid required consent before Profile / Home']),
 'profile':('UC300 Manage profile and optional plan refresh',[
  'Open an owned profile section and load lookup choices','Edit body values, conditions/status, limitations and food exclusions',('Mandatory values and combined body values valid?','Identify invalid fields; keep the unsaved draft'),
  'Derive declared-profile risk, safety limits and profile version',('Profile save succeeds?','Keep prior stored profile; allow retry'),
  ('Diet-affecting change and Update plans selected?','Keep saved plans and logged meal history'),
  'Generate current/saved weekly replacement through strict AI gates','Show successful or partial refresh; preserve any failed plan']),
 'health_connect':('UC300 and UC700 Connect Health Connect',[
  'Open Health Data Connection / Import readings',('Source installed and supported?','Offer install/update or explain unsupported platform'),
  ('Required read permissions granted?','Open permission guidance; retain stored readings'),
  'Read available supported records; retain original measurement times',('Valid, nonfuture and not a duplicate?','Ignore rejected/duplicate rows; never invent a reading'),
  'Save accepted records with first import time and source','Show new-record count and successful-check state']),
 'health_report':('UC600 Review health results and explanations',[
  'Load account profile, readings, meals, activity and saved analyses',('Inputs available for the individual calculation?','Withhold that result and explain missing inputs'),
  'Request supported risk / forecast outputs and calculate score factors',('AI request succeeds?','Show available saved result as stale; offer retry'),
  'Render measured history, uncertainty and result provenance','Explain conclusion, analysis and suggested next step',('A high-severity recorded alert needs review?','Continue report without a new high alert'),
  'Display warning and existing professional-review advice']),
 'tracking':('UC700 Track measurements and exercise sessions',[
  'Load selected period, original records, exercise history and sources','Choose Pressure, Glucose, Weight or Exercise','Inspect actual points, change dates, zoom/pan or reset',('A record exists at the selected point?','Clear vertical selection/details for an empty gap'),
  'Show original time, source/import time or available session metadata','Add a manual reading or check a connected source',('Entry/import is valid and persistence succeeds?','Keep form/prior history and explain retry'),
  'Refresh counts and graphs; retain unknown/unavailable distinctions']),
 'watch_import':('UC700 Import supported saved watch history',[
  'Keep Bluetooth on; disconnect competing companion-app ownership','Scan/select a compatible supported watch or restore saved selection',('Watch protocol exposes a saved measurement?','Report no new saved records / unsupported capability'),
  'Read available blood pressure, glucose or weight records',('Measurement valid, nonfuture and new by original time?','Skip duplicates/invalid rows; keep nearby distinct readings'),
  'Save original recorded_at, source/device and first imported_at','Refresh new-record count and last successful watch check','Repeat while active about every 15 seconds; skip concurrent checks']),
 'graph':('UC700 Select period and inspect graph data',[
  'Choose 7, 30, 90 days or a custom local-date range',('Start date is not later than end date?','Keep prior range; explain invalid selection'),
  'Load matching measurements / completed sessions','Zoom, pan or reset the horizontal time window',('A recorded point is selected?','Hide selection details; missing values stay unknown'),
  'Show vertical line and point details; daily exercise lists its sessions']),
 'food':('UC800 Review multiple foods and log actual intake',[
  'Choose camera, gallery or manual entry; show saved-plan reminder',('Photo source selected and original image valid?','Use another source or manual catalogue entry'),
  'Prepare JPEG at most 1024 px; send image/codes to owned server',('Usable catalogue-mapped recognition result?','Explain local fallback or offer retry/manual entry'),
  'Review every food, estimated count and total edible grams','Correct/add missed foods, merge repeats and reassess warnings',('Patient confirms meal and storage succeeds?','Keep review draft; undo failed optimistic save'),
  'Store meal/nutrient snapshots, review metadata and optional photo']),
 'manual_food':('UC800 Enter actual foods manually',[
  'Start a manual meal or continue after recognition failure','Search and select a catalogue food','Set edible grams and optional count; recalculate nutrition',('Combined food quantity is valid?','Reject change; preserve the prior draft'),
  'Merge repeat food selection into one row; show red health warnings','Review actual meal; optional isolated simulator',('Patient chooses Save and write succeeds?','Cancel or retain draft for correction/retry'),
  'Update saved history and daily totals']),
 'amend_food':('UC800 Correct food identities and portions',[
  'Choose a draft food to replace, resize, add or remove','Review total grams, count and unit-weight estimate',('Updated or merged meal-entry amount is valid?','Retain existing item and explain the allowed range'),
  'Merge matching foods; recalculate catalogue nutrients once','Reassess profile/remaining-allowance warnings','Keep draft in review until an explicit Save']),
 'diet':('UC900 Review recommendations and patient choices',[
  'Load current profile, saved foods and logged daily intake','Explain suitability, portion reasons and target coverage','Offer suitable alternatives or patient catalogue choices',('Patient-selected edit is structurally valid?','Block malformed amount/date or empty selection'),
  'Merge repeated food/date/slot portions; show red health conflicts',('Patient confirms edit and save succeeds?','Keep prior plan/draft and explain failure'),
  'Persist chosen foods with warnings; do not claim AI approval']),
 'daily_plan':('UC900 Generate or replan today',[
  'Read current profile, locked foods, actual logs and history','Request candidate plan; do not count planned and logged food twice',('Every AI portion and daily nutrition gate passes?','Retry candidate, at most 3 attempts; otherwise keep saved plan'),
  'Keep locked rows only when they pass current-profile rules',('All requested generation checks and write succeed?','No invalid new AI plan is persisted; offer retry/manual build'),
  'Show new plan and allowance; retain logged history']),
 'weekly_plan':('UC900 Open saved dates or schedule future plans',[
  'Open Weekly plan focused on today; choose another saved date',('A future period is requested?','Read saved daily/overlapping multi-day plan without generation'),
  'Choose day/week/month preset or explicit start/end dates',('Future start and 1–31 inclusive days are valid?','Explain dates and preserve prior plan'),
  'Generate validated weekly/daily blocks with current context',('Every requested date passes and period save succeeds?','Discard partial new result; retain saved plans'),
  'Open selected plan date; food taps show that date\'s details']),
 'profile_retrieve':('UC1000 Retrieve authenticated profile context',[
  'Including workflow requests current profile context',('An authenticated account is available?','Return authentication failure without profile data'),
  'Read that account\'s profile and saved safety limits',('Profile and required values are available?','Return explicit missing/incomplete/error status and conservative limits'),
  'Return complete/stale snapshot; generate limits if not stored','Caller guards account changes and discloses conservative handling']),
 'insights':('UC610 to UC640 Review insights without changing treatment',[
  'Load owned plans, meals, readings, sessions and diary history','Choose week/day and include/exclude tagged presentation data','Inspect timeline, weekly facts or data quality with coverage',('Save/edit a recovery check-in?','Inspect records or export the same weekly snapshot'),
  'Validate assignment/date, scores and note length',('Ownership, uniqueness and write checks pass?','Keep diary input and prior state; explain retry'),
  'Reload diary; compare symptoms within assignment and posture within exercise','Treatment progress remains unchanged']),
 'comparison':('UC810 and UC910 Compare meals and review food options',[
  'Choose week/day; match account, date, meal slot and food key',('Applicable saved plan existed before the logged meal?','Mark reference/no-plan/missing/unavailable; no adherence claim'),
  'Explain changed food grams, nutrient differences and coverage','Derive current-profile daily options and weekly occurrence totals',('Increase fits current suitability and daily budgets?','Withhold unsupported increase; state any required conditional swap'),
  'Open separate meal proposal; edit foods and preview 6 nutrients',('Explicit Use in meal draft / acknowledgement selected?','Reset/cancel keeps original draft unchanged'),
  'Return to normal meal review; no automatic meal save'])
}
for name,(title,steps) in FLOWS.items():flow(name,title,steps)

def sequence(name,title,people,messages):
    w=1500;top=195;gap=104;h=top+len(messages)*gap+70
    im,dr=canvas(w,h);label(dr,(10,4,w-10,65),title,32,True)
    xs=[150+i*300 for i in range(len(people))]
    assert len(people)==5
    for x,p in zip(xs,people):
        box(dr,(x-135,77,x+135,190),p,25,True)
        for y in range(top,h-25,19):dr.line((x,y,x,y+10),fill='#A0A6AC',width=2)
    for i,(a,b,message) in enumerate(messages):
        y=top+64+i*gap
        if a==b:
            arrow(dr,[(xs[a],y),(xs[a]+70,y),(xs[a]+70,y+32),(xs[a],y+32)])
            label(dr,(xs[a]-130,y-55,xs[a]+138,y-6),message,22)
        else:
            arrow(dr,[(xs[a],y),(xs[b],y)],dashed=message.startswith('return:'))
            lo,hi=sorted([xs[a],xs[b]])
            label(dr,(lo+5,y-81,hi-5,y-7),message.replace('return:',''),24)
    save(im,name)

SEQS={
 'seq_register':('UC100 Account activation and current-version consent',['Patient','Auth\nViewModel','Auth repository\ninterface','Terms repository\ninterface','Profile repository\ninterface'],[(0,1,'Register / verify'),(1,2,'Create / activate'),(2,1,'return:account / failure'),(1,3,'Latest acceptance'),(3,1,'return:current / missing'),(1,0,'Required terms form'),(0,1,'Accept valid declarations'),(1,3,'Save versioned record'),(1,4,'Profile completion'),(4,1,'return:setup / complete'),(1,0,'Profile / Home route')]),
 'seq_login':('UC200 Authenticate before consent and profile routing',['Patient','Auth\nViewModel','Auth repository\ninterface','Terms repository\ninterface','Profile repository\ninterface'],[(0,1,'Login / restore session'),(1,2,'Authenticate / session'),(2,1,'return:account / failure'),(1,3,'Current acceptance?'),(3,1,'return:status / absent'),(1,0,'Review terms if needed'),(0,1,'Accept or decline'),(1,3,'Save valid acceptance'),(1,4,'Profile completion'),(4,1,'return:setup / complete'),(1,0,'Profile / Home route')]),
 'seq_profile':('UC300 Save profile and optional diet refresh',['Patient','Profile\nViewModel','Profile repository\ninterface','Risk / safety\nlogic','Diet plan\nViewModel'],[(0,1,'Edit / Save'),(1,2,'Load / persist profile'),(2,1,'return:stored profile'),(1,3,'Derive risk / limits'),(3,1,'return:current context'),(1,0,'Ask Update plans?'),(0,1,'Consent or Not now'),(1,4,'Refresh if consented'),(4,0,'Result / retained plans')]),
 'seq_health':('UC600 Request and explain available health results',['Patient','Analysis\nViewModel','Repository\ninterfaces','Analysis / forecast\nservices','Owned AI\nserver'],[(0,1,'Open / Refresh'),(1,2,'Load owned history'),(2,1,'return:records / failures'),(1,3,'Check required inputs'),(3,4,'De-identified request'),(4,3,'return:result / withheld'),(3,1,'return:decoded results'),(1,2,'Persist valid result'),(1,0,'Explain / label stale')]),
 'seq_tracking':('UC700 Save original-time health records',['Patient / timer','Monitoring\nViewModel','Source adapter /\nHealthConnectService','Biometric repository\ninterface','Tracking\nview'],[(0,1,'Entry / source check'),(1,2,'Read saved records'),(2,1,'return:times / capabilities'),(1,1,'Validate / deduplicate'),(1,3,'Insert accepted batch'),(3,1,'return:new-record count'),(1,2,'Save source check time'),(1,3,'Reload chosen range'),(3,1,'return:stored history'),(1,4,'Notify graph / details')]),
 'seq_food':('UC800 Recognise then explicitly save reviewed food',['Patient','MealLog\nViewModel','FoodRecognition\nService','Owned AI\nserver','Meal repository\ninterface'],[(0,1,'Choose photo / manual'),(1,2,'Prepare / recognise'),(2,3,'Image + declared codes'),(3,2,'return:foods / estimates'),(2,1,'return:catalogue items'),(1,0,'Review quantities'),(0,1,'Correct / merge / Save'),(1,4,'Meal + snapshots / photo'),(4,1,'return:save / failure'),(1,0,'Refresh or keep draft')]),
 'seq_diet':('UC900 Reject invalid AI plans before persistence',['Patient','DietPlan\nViewModel','DietPlanner\nService','Owned AI\nserver','Meal repository\ninterface'],[(0,1,'Generate / Replan'),(1,4,'Read plan / logs'),(4,1,'return:owned records'),(1,2,'Current context / locks'),(2,3,'Request candidate'),(3,2,'return:planned foods'),(2,2,'Gate / retry max 3'),(2,1,'return:valid or failure'),(1,4,'Save valid full period'),(1,0,'Display / preserve old')]),
 'seq_profile_retrieve':('UC1000 Return status without guessing missing values',['Including workflow','RiskAssessment\nService','Auth repository\ninterface','Profile repository\ninterface','Caller\nViewModel'],[(0,1,'Retrieve context'),(1,2,'Current account'),(2,1,'return:account / absent'),(1,3,'Profile / saved limits'),(3,1,'return:stored / unavailable'),(1,1,'Set status / limits'),(1,4,'return:snapshot / failure'),(4,4,'Guard account / request'),(4,0,'Usable / conservative')]),
 'seq_insights':('UC610 to UC630 Share the loaded report snapshot',['Patient','HealthInsights\nViewModel','Repository\ninterfaces','HealthInsights /\nfood guidance services','WeeklyReport\nService'],[(0,1,'Choose week / filter'),(1,2,'Read owned records'),(2,1,'return:data / notices'),(1,3,'Build facts / guidance'),(3,1,'return:dated snapshot'),(1,0,'Render evidence'),(0,1,'Export / Print'),(1,4,'Same loaded snapshot'),(4,1,'return:offline PDF bytes'),(1,0,'System dialog / retry')]),
 'seq_recovery':('UC640 Save diary without advancing treatment',['Patient','HealthInsights\nViewModel','IRecovery\nRepository','Supabase /\nPostgreSQL','Treatment repository\ninterface'],[(0,1,'Assignment/date / scores'),(1,1,'Validate form'),(1,2,'Insert / update entry'),(2,3,'Owned unique diary row'),(3,2,'return:saved / rejected'),(2,1,'return:entry / failure'),(1,4,'Reload session evidence'),(4,1,'return:unchanged progress'),(1,0,'Diary / review warning')])
}
for name,args in SEQS.items():sequence(name,*args)

def cards(name,title,rows,edges,footer='Arrows show documented dependencies or labelled associations.'):
    w=1500;rh=305;h=130+len(rows)*rh+100
    im,dr=canvas(w,h);label(dr,(10,5,w-10,70),title,32,True)
    coords={}
    for ri,row in enumerate(rows):
        count=len(row);cw=1440/count
        for ci,(key,heading,body) in enumerate(row):
            x=30+ci*cw;y=105+ri*rh;rect=(int(x+10),y,int(x+cw-10),y+220)
            box(dr,rect,'',fill='white')
            dr.line((rect[0],y+90,rect[2],y+90),fill='#343A40',width=2)
            label(dr,(rect[0]+4,y+3,rect[2]-4,y+85),heading,25,True)
            label(dr,(rect[0]+8,y+96,rect[2]-8,y+214),body,23,False,'left')
            coords[key]=rect
    for a,b,caption in edges:
        ra,rb=coords[a],coords[b]
        if ra[1]==rb[1]:
            p=(ra[2],(ra[1]+ra[3])/2);q=(rb[0],(rb[1]+rb[3])/2)
            if p[0]>q[0]:p=(ra[0],p[1]);q=(rb[2],q[1])
        else:
            p=((ra[0]+ra[2])/2,ra[3]);q=((rb[0]+rb[2])/2,rb[1])
        if q[1]-p[1]>110:
            entry=(rb[2],(rb[1]+rb[3])/2)
            arrow(dr,[p,(p[0],p[1]+10),(1485,p[1]+10),(1485,entry[1]),entry])
            continue
        y=(p[1]+q[1])/2
        arrow(dr,[p,(p[0],y),(q[0],y),q])
        if caption:
            tw=dr.textlength(caption,font=font(21))
            cx=(p[0]+q[0])/2
            dr.rectangle((cx-tw/2-6,y-24,cx+tw/2+6,y+4),fill='white')
            dr.text((cx-tw/2,y-23),caption,font=font(21),fill='#20262B')
    label(dr,(25,h-95,w-25,h-10),footer,23)
    save(im,name)

cards('architecture','Current MVVM layers and deployment boundaries',[
 [('views','Views','Diet, Tracking, Health Report\nHealth insights and recovery UI')],
 [('vms','ViewModels','Observable state, commands\nDrafts, loading and account guards')],
 [('logic','Business logic services','Suitability, generation, comparisons\nInsights, simulation, PDF and explanations')],
 [('repos','Repository interfaces','Account-scoped persistence\nConcrete repositories wired in main.dart'),('api','Shared API client','Authenticated inference calls\nNo database persistence in AI server'),('device','Device platform adapters','Health Connect / direct-watch bridge\nCamera, local settings and notifications')],
 [('supabase','Supabase','Auth, relational records, RLS\nPrivate meal-photo storage'),('server','Owned FastAPI server','Food, forecast, risk, posture\nOptional external vision provider')]
], [('views','vms','commands / state'),('vms','logic','calculate'),('logic','repos','read / write contracts'),('logic','api','inference'),('vms','device','device commands'),('repos','supabase','shared database client'),('api','server','HTTP API')], 'Views contain no database queries. Model inference and record persistence have separate boundaries.')
cards('profile_classes','Profile classes and declared safety context',[
 [('vm','ProfileViewModel','draft / profile / choices\nsaveProfile(), loadProfile()'),('risk','RiskAssessmentService','retrieve() -> profile snapshot\nDerive declared risk / safety limits')],
 [('profile','HealthProfile','Body values, conditions/status\nrestrictions, limitations, version'),('snapshot','ProfileSnapshot','ProfileStatus + SafetyLimit\nComplete / stale / unavailable')],
 [('lookup','Condition / exclusion lookups','HealthCondition, DietaryRestriction\nPhysicalLimitation'),('limit','SafetyLimit / DietContext','Exercise caps and diet targets\nCurrent-rule evaluation context')]
], [('vm','profile','edits'),('risk','snapshot','returns'),('profile','lookup','declares'),('snapshot','limit','carries')])
cards('tracking_classes','Tracking classes and supported-source adapters',[
 [('vm','MonitoringViewModel','loadRange(), startAutoSync()\nimportWatchHistory(), syncWatch()')],
 [('source','HealthConnectService','readRecords(), permissions\nPlatform read-only source'),('watch','VeepooWatchSource','scan(), readConnected()\nWatchConnection / WatchHistory'),('repo','IBiometricRepository','insertBatch(), findBetween()\nrecordImport(), source state')],
 [('reading','BiometricReading','recordedAt / importedAt\nsourceDevice / metric / values'),('activity','ActivityRecord','Original completedAt / duration\nPlan, reps, posture, demo status'),('data','MonitoringData','Readings, sessions and summary\nsessionsAvailable / chosen range')]
], [('vm','source','checks'),('vm','watch','checks'),('vm','repo','persists'),('source','reading','maps'),('vm','activity',''),('vm','data','')], 'ActivityRecord comes from completed treatment sessions through the treatment repository, not from a watch measurement.')
cards('diet_classes','Diet entities and review metadata',[
 [('meal','MealLog','Owned meal, local time, image\nSaved nutrient snapshots'),('plan','DietPlan','startDate / endDate / type\nGenerated or patient-selected foods')],
 [('item','MealItem','Food, edible grams, nutrients\nOptional recognitionDetails'),('planned','PlannedMeal','planDate / slot / grams\nLocked / logged flags')],
 [('details','FoodRecognitionDetails','Count, unit and unitWeightG\nEstimated / reviewed / boxes'),('food','FoodItem','Catalogue values per 100 g\nExclusion codes and extra nutrients')],
 [('comparison','PlanComparisonReport','Day / meal / food differences\nReference / missing states'),('guidance','DietFoodGuidance','DailyFoodGuidance + actions\nWeekly priorities + evidence dates')]
], [('meal','item','1 to many'),('plan','planned','1 to many'),('item','details','optional'),('planned','food','catalogue food')], 'Comparison and guidance are derived from meals/plans by services, not persisted meal histories. See the service specifications.')
cards('insights_classes','Shared insight and recovery classes',[
 [('vm','HealthInsightsViewModel','load(), exportReport()\nsaveCheckIn(), deleteCheckIn()')],
 [('service','HealthInsightsService','Build timeline / facts / coverage\nOwned records and demo filter'),('guide','DietFoodGuidanceService','Current-profile portion options\nConditional swaps and weekly groups'),('repo','IRecoveryRepository','findBetween(), save(), delete()\nOwned diary persistence')],
 [('data','HealthInsights','Selected snapshot and notices\nTimeline, comparison, foodGuidance'),('pdf','WeeklyReportService','create(snapshot) -> PDF bytes\nSame facts and guidance as UI'),('diary','RecoveryCheckIn','Plan/date, scores and notes\nDemo status, server updatedAt')]
], [('vm','service','build'),('service','guide','calls'),('vm','repo','persist'),('service','data','returns'),('vm','pdf',''),('repo','diary','stores')], 'HealthInsightsService invokes food guidance. PDF receives the same snapshot. Diary writes never update treatment progress.')
cards('components','Current mobile components and external integrations',[
 [('ui','Flutter mobile presentation','Profile / Tracking / Diet / Treatment\nHealth Report / Health insights')],
 [('model','Application Model and ViewModels','Commands, rules, repositories\nLocal comparisons, PDF and diary')],
 [('db','Supabase services','Authentication / RLS / Storage\nAccount-owned clinical-style records'),('ml','Owned FastAPI subsystem','Stateless inference endpoints\nOptional online food vision'),('device','Android platform','Health Connect / Bluetooth adapter\nCamera, print UI and notifications')]
], [('ui','model','commands / state'),('model','db','repository contracts'),('model','ml','API client'),('model','device','platform adapters')])
cards('deployment','Current deployment and privacy boundaries',[
 [('phone','Android phone','Flutter app, device adapters\nPatient review and explicit saves')],
 [('watch','Compatible wearable / Health Connect','Saved measurements exposed\nOnly supported protocols and metrics'),('backend','Supabase cloud','Account records and meal images\nAuth / RLS ownership checks'),('fastapi','Laptop or hosted FastAPI','Prepared images / de-identified features\nBearer-authenticated inference')],
 [('none','Local derived reports','Comparison, food options and PDF\nNo external narrative upload'),('vision','Optional online vision provider','Prepared image and catalogue context\nNo profile codes or session credentials')]
], [('phone','watch','Bluetooth / platform API'),('phone','backend','authenticated data access'),('phone','fastapi','inference API'),('fastapi','vision','optional image request')], 'Public deployment uses HTTPS; local development endpoints are explicitly configured. No server-side secret is shipped in the app.')
cards('storage','Storage extensions and derived report boundary',[
 [('account','account','account_id primary key\nOwns all patient records'),('plan','patient_plan','patient_plan_id primary key\naccount_id foreign key')],
 [('diary','recovery_check_in','account_id + patient_plan_id + date\nUnique; validated scores / RLS'),('reading','biometric_reading','Original recorded_at, source/device\nFirst-save imported_at')],
 [('meal','meal_log / meal_item','Nutrient snapshots + photo link\nrecognition_details JSONB on item'),('derived','Derived snapshot objects','PlanComparisonReport / HealthInsights\nDietFoodGuidance / MealSimulation')]
 , [('terms','terms_acceptance','Append-only account/version/time\nExplicit consent, age/guardian declaration')]
], [('account','plan','1 to many'),('account','diary','owns'),('plan','diary','1 to many'),('account','reading','owns'),('account','terms','')], 'Terms and symptom records are separate. Derived reports are not new tables; a diary write does not advance treatment.')

def usecases():
    im,dr=canvas(1480,1230)
    label(dr,(20,5,1460,75),'Current use-case extensions within HealthGuide',32,True)
    dr.rounded_rectangle((360,105,1450,1150),radius=10,outline='#343A40',width=3)
    dr.text((385,120),'HealthGuide application boundary',font=font(26,True),fill='#151515')
    x=155;y=550
    dr.ellipse((x-25,y-130,x+25,y-80),outline='#20262B',width=4)
    dr.line((x,y-80,x,y+25),fill='#20262B',width=4)
    dr.line((x-60,y-40,x+60,y-40),fill='#20262B',width=4)
    dr.line((x,y+25,x-50,y+100),fill='#20262B',width=4)
    dr.line((x,y+25,x+50,y+100),fill='#20262B',width=4)
    label(dr,(55,y+110,255,y+170),'Patient',28,True)
    labels=['UC610 Review health timeline','UC620 Review/export weekly progress','UC630 Review data quality','UC640 Manage recovery check-in','UC810 Simulate meal changes','UC910 Compare planned/logged meals']
    for i,t in enumerate(labels):
        yy=205+i*145
        dr.ellipse((505,yy,1335,yy+100),fill='#F5F6F7',outline='#343A40',width=3)
        label(dr,(520,yy+5,1320,yy+95),t,28,True)
        dr.line((220,y-30,505,yy+50),fill='#777E84',width=2)
    label(dr,(375,1035,1430,1140),'UC800 may extend to UC810 during draft review. UC900 links to UC910. Profile context is retrieved through UC1000; AI server logic remains inside the deployed system.',24)
    save(im,'use_cases')
usecases()
print(f'{len(list(OUT.glob("*.png")))} diagrams written to {OUT}')
