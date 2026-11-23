/// What research reports about each kind of exercise, for the posture result screen (Elwin,
/// 10 Nov: "the benefits shown should be according to relevant research paper ... with the
/// hyperlink"; 11 Nov: "more information but less wordings and more readability"). Each group
/// cites a systematic review that was checked on 10 Nov 2026; the numbers are the ones those
/// reviews report. The screen shows the benefits in the patient's words ([benefits]); the key
/// numbers ([facts]), the full finding, the citation and the caveat are behind "More". A timing is given only where
/// the review states it (back pain: three months after the start).
///
/// These are averages from studies of other patients, mostly adults with osteoarthritis, back pain
/// or older age, so the screen says so and does not promise the same result.
library;

class EvidenceSource {
  /// Short citation shown on the screen, e.g. "Fransen et al. (2015)".
  final String citation;
  final String title;
  final String journal;

  /// DOI link, opened in the phone's browser.
  final String url;

  const EvidenceSource({
    required this.citation,
    required this.title,
    required this.journal,
    required this.url,
  });
}

/// One key number of a review: [value] in large type, [label] under it.
typedef EvidenceFact = ({String value, String label});

/// What a benefit is about; the view gives each kind its icon.
enum BenefitKind {
  pain,
  walking,
  strength,
  standing,
  falls,
  movement,
  practice,
  daily,
}

/// One benefit in the patient's words, e.g. "Less knee pain" (15 Nov).
typedef EvidenceBenefit = ({BenefitKind kind, String text});

class EvidenceGroup {
  final String id;

  /// What the exercise trains, e.g. "Knee and leg strength".
  final String title;

  /// What the patient can expect, in plain words: shown first, the numbers are behind "More".
  final List<EvidenceBenefit> benefits;

  /// Two or three key numbers from the review (behind "More").
  final List<EvidenceFact> facts;

  /// What the review found, in full sentences (behind "More").
  final String finding;

  /// Short study result under the outlook graph, e.g. "−15 back pain (of 100)".
  final String outcome;

  /// Weeks from the start at which the review measured [outcome], when it says so.
  final int? weeks;
  final EvidenceSource source;

  const EvidenceGroup({
    required this.id,
    required this.title,
    required this.benefits,
    required this.facts,
    required this.finding,
    required this.outcome,
    required this.source,
    this.weeks,
  });
}

abstract final class ExerciseEvidence {
  /// One line under the key numbers.
  static const caveat = 'Study averages from other patients, not a promise.';

  /// In "More": who to ask.
  static const caveatMore =
      'Your own results may differ. Ask your healthcare professional if you are unsure.';

  /// With a score of 80% or more.
  static const whenPassing = 'Good form: the way the studies did it.';

  /// Below 80%.
  static const whenBelow = 'Fix the form first: the studies used correct form.';

  static const knee = EvidenceGroup(
    id: 'knee',
    title: 'Knee and leg',
    benefits: [
      (kind: BenefitKind.pain, text: 'Less knee pain'),
      (kind: BenefitKind.walking, text: 'Easier to move about'),
    ],
    facts: [
      (value: '−12', label: 'pain\n(of 100)'),
      (value: '+10', label: 'function\n(of 100)'),
    ],
    finding:
        'In a Cochrane review of exercise for knee osteoarthritis, people who finished an exercise '
        'programme rated their knee pain about 32 out of 100, against 44 for people who did not '
        'exercise, and their physical function improved by about 10 points out of 100.',
    outcome: 'less knee pain, better function',
    source: EvidenceSource(
      citation: 'Fransen et al. (2015)',
      title: 'Exercise for osteoarthritis of the knee',
      journal: 'Cochrane Database of Systematic Reviews, CD004376',
      url: 'https://doi.org/10.1002/14651858.CD004376.pub3',
    ),
  );

  static const strength = EvidenceGroup(
    id: 'strength',
    title: 'Muscle strength',
    benefits: [
      (kind: BenefitKind.strength, text: 'Stronger muscles'),
      (kind: BenefitKind.standing, text: 'Easier to stand up from a chair'),
      (kind: BenefitKind.walking, text: 'Slightly faster walking'),
    ],
    facts: [
      (value: 'Large', label: 'strength\ngain'),
      (value: 'Easier', label: 'rising from\na chair'),
      (value: '2–3×', label: 'a week in\nthe trials'),
    ],
    finding:
        'A Cochrane review of 121 trials in older adults found that strength training, mostly '
        'two to three times a week, gave large gains in muscle strength, made rising from a chair '
        'easier and walking slightly faster.',
    outcome: 'stronger muscles, easier chair rise',
    source: EvidenceSource(
      citation: 'Liu & Latham (2009)',
      title:
          'Progressive resistance strength training for improving physical function in older adults',
      journal: 'Cochrane Database of Systematic Reviews, CD002759',
      url: 'https://doi.org/10.1002/14651858.CD002759.pub2',
    ),
  );

  static const balance = EvidenceGroup(
    id: 'balance',
    title: 'Balance',
    benefits: [(kind: BenefitKind.falls, text: 'About a quarter fewer falls')],
    facts: [(value: '−23%', label: 'falls'), (value: '108', label: 'trials')],
    finding:
        'A Cochrane review of 108 trials in older people living at home found that exercise '
        'reduced the number of falls by about a quarter (23%), and that programmes based mainly '
        'on balance and functional exercises reduce falls (high-certainty evidence).',
    outcome: '−23% falls',
    source: EvidenceSource(
      citation: 'Sherrington et al. (2019)',
      title:
          'Exercise for preventing falls in older people living in the community',
      journal: 'Cochrane Database of Systematic Reviews, CD012424',
      url: 'https://doi.org/10.1002/14651858.CD012424.pub2',
    ),
  );

  static const shoulder = EvidenceGroup(
    id: 'shoulder',
    title: 'Shoulder',
    benefits: [
      (kind: BenefitKind.pain, text: 'Less shoulder pain'),
      (kind: BenefitKind.movement, text: 'Wider arm movement'),
    ],
    facts: [
      (value: 'Less', label: 'pain'),
      (value: 'More', label: 'movement'),
      (value: '64', label: 'trials'),
    ],
    finding:
        'A systematic review of 64 trials of shoulder pain found strong evidence that exercise '
        'therapy improves pain, function and range of movement in the short, middle and long '
        'term, as well as surgery does and better than no treatment.',
    outcome: 'less pain, more movement',
    source: EvidenceSource(
      citation: 'Haik et al. (2016)',
      title:
          'Effectiveness of physical therapy treatment of clearly defined subacromial pain: '
          'a systematic review of randomised controlled trials',
      journal: 'British Journal of Sports Medicine, 50(18), 1124-1134',
      url: 'https://doi.org/10.1136/bjsports-2015-095771',
    ),
  );

  static const back = EvidenceGroup(
    id: 'back',
    title: 'Core and back',
    benefits: [
      (kind: BenefitKind.pain, text: 'Less back pain'),
      (kind: BenefitKind.daily, text: 'Easier daily activities'),
    ],
    facts: [
      (value: '−15', label: 'pain\n(of 100)'),
      (value: '−7', label: 'disability\n(of 100)'),
      (value: '12 wk', label: 'when\nmeasured'),
    ],
    finding:
        'A Cochrane review of 249 trials of exercise for long-lasting low back pain found pain '
        'about 15 points lower and disability about 7 points lower out of 100, three months '
        'after the start of treatment.',
    outcome: '−15 back pain (of 100)',
    weeks: 12,
    source: EvidenceSource(
      citation: 'Hayden et al. (2021)',
      title: 'Exercise therapy for chronic low back pain',
      journal: 'Cochrane Database of Systematic Reviews, CD009790',
      url: 'https://doi.org/10.1002/14651858.CD009790.pub2',
    ),
  );

  /// Each exercise of the catalogue (assets/seed/catalogue.json) and the evidence it belongs to.
  static const byExercise = <String, EvidenceGroup>{
    'Seated Knee Extension': knee,
    'Mini Squat': knee,
    'Step-Up': knee,
    'Standing Hip Abduction': knee,
    'Sit-to-Stand': strength,
    'Elbow Flexion': strength,
    'Wall Push-Up': strength,
    'Tandem Stance': balance,
    'Heel Raise': balance,
    'March in Place': balance,
    'Seated Marching': balance,
    'Shoulder Abduction': shoulder,
    'Shoulder Flexion': shoulder,
    'Bird Dog': back,
    'Glute Bridge': back,
  };

  static EvidenceGroup? forExercise(String? name) =>
      name == null ? null : byExercise[name];
}
