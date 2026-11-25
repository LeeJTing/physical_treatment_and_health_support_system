"""Validate the source artefacts, without application or database writes."""
from pathlib import Path
from collections import Counter
import json,re

BASE=Path(__file__).parent
APP=BASE.parents[2]
SERVER=Path(r'C:\Users\User\Documents\GitHub\fyp-fastapi')
spec=json.loads((BASE/'specification.json').read_text(encoding='utf-8'))
cases=json.loads((BASE/'use_cases.json').read_text(encoding='utf-8'))
classes=json.loads((BASE/'class_specifications.json').read_text(encoding='utf-8'))
ids=[]
for name,text in spec['changed_requirements'].items():
    assert re.fullmatch(r'FR\d{3}_\d{3}',name),name
    assert text.startswith('The system shall '),name
for rows in spec['added_requirements'].values():
    for name,text in rows:
        assert re.fullmatch(r'FR\d{3}_\d{3}',name),name
        assert text.startswith('The system shall '),name
        ids.append(name)
assert len(ids)==len(set(ids))
assert not(set(ids)&set(spec['changed_requirements']))
seen=[]
for c in cases:
    seen.append(c['id'])
    assert re.fullmatch(r'UC\d+',c['id'])
    assert all(c.get(k) for k in ['title','description','pre','post','flow','alternatives','exceptions','notes','requirements','sources']),c['id']
    assert all(len(step)==2 and step[1] and (step[0] or c['id']=='UC1000') for step in c['flow']),c['id']
    for file in c['sources']:
        target=(SERVER/file) if file.startswith('ai_server/') else APP/file
        assert target.is_file(),(c['id'],target)
assert len(seen)==len(set(seen))
app_source='\n'.join(p.read_text(encoding='utf-8') for p in (APP/'lib').rglob('*.dart'))
for name,description,rows in classes:
    assert re.search(r'\bclass\s+'+re.escape(name)+r'\b',app_source),name
    assert description and rows and all(len(r)==4 for r in rows),name
figures=list((BASE/'figures').glob('*.png'))
assert len(figures)==38,len(figures)
result={'changed_existing_requirements':len(spec['changed_requirements']),'added_requirements':len(ids),'reviewed_use_cases':len(cases),'class_specifications':len(classes),'diagram_files':len(figures),'source_paths_verified':True,'standard':'Existing shall statements and Patient/System use-case structure; no external certification claim.'}
(BASE/'validation.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps(result,indent=2))
