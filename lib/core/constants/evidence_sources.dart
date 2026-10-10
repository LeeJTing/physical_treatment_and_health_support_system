/// The papers and guidelines behind the plan rules, keyed as the AI server sends them with each
/// reason ("why this plan" / "why not"). A reason with no key is our own design choice: the app
/// labels it [appRuleLabel]. Every key the server can send must be here (ai_server
/// tests/test_recommend.py checks). Full list: fyp-notes/Evidence_Plan_Tailoring.docx.
class EvidenceSource {
  const EvidenceSource(this.short, this.reference, this.usedFor);

  /// In-text form, e.g. "Campbell & Robertson (2003)".
  final String short;

  /// Full APA reference.
  final String reference;

  /// What the app uses it for, in plain words.
  final String usedFor;
}

class EvidenceSources {
  EvidenceSources._();

  static const String appRuleLabel = 'App safety rule';

  static const Map<String, EvidenceSource> all = {
    'acsm2009': EvidenceSource(
      'Chodzko-Zajko et al. (2009)',
      'Chodzko-Zajko, W. J., Proctor, D. N., Fiatarone Singh, M. A., Minson, C. T., Nigg, C. R., Salem, G. J., & '
          'Skinner, J. S. (2009). American College of Sports Medicine position stand: Exercise and physical '
          'activity for older adults. Medicine & Science in Sports & Exercise, 41(7), 1510-1530.',
      'Strength on at least 2 days a week, 8-12 repetitions, moderate effort; balance and flexibility work.',
    ),
    'billinger2014': EvidenceSource(
      'Billinger et al. (2014)',
      'Billinger, S. A., Arena, R., Bernhardt, J., et al. (2014). Physical activity and exercise recommendations '
          'for stroke survivors: A statement from the American Heart Association/American Stroke Association. '
          'Stroke, 45(8), 2532-2553.',
      'Increase exercise only "as tolerance permits"; warm-up and cool-down; stroke safety.',
    ),
    'colberg2016': EvidenceSource(
      'Colberg et al. (2016)',
      'Colberg, S. R., Sigal, R. J., Yardley, J. E., et al. (2016). Physical activity/exercise and diabetes: A '
          'position statement of the American Diabetes Association. Diabetes Care, 39(11), 2065-2079.',
      'Exercise limits and low blood sugar precautions for diabetes.',
    ),
    'haff2016': EvidenceSource(
      'Haff & Triplett (2016)',
      'Haff, G. G., & Triplett, N. T. (Eds.). (2016). Essentials of strength training and conditioning '
          '(4th ed.). Human Kinetics.',
      'Move up a level after doing more than asked in two sessions in a row ("2-for-2").',
    ),
    'hk_doh': EvidenceSource(
      'Department of Health, Hong Kong (n.d.)',
      "Department of Health, Hong Kong. (n.d.). Recommendations for prescribing exercise to patients with "
          "hypertension (Chapter 7). In Exercise prescription: Doctors' handbook.",
      'Exercise limits for high blood pressure.',
    ),
    'icfsr2021': EvidenceSource(
      'Izquierdo et al. (2021)',
      'Izquierdo, M., Merchant, R. A., Morley, J. E., et al. (2021). International exercise recommendations in '
          'older adults (ICFSR): Expert consensus guidelines. The Journal of Nutrition, Health & Aging, 25(7), '
          '824-853.',
      'Start light and progress; 2-3 strength days a week with a rest day between.',
    ),
    'lacroix2017': EvidenceSource(
      'Lacroix et al. (2017)',
      'Lacroix, A., Hortobágyi, T., Beurskens, R., & Granacher, U. (2017). Effects of supervised vs. '
          'unsupervised training programs on balance and muscle strength in older adults: A systematic review '
          'and meta-analysis. Sports Medicine, 47(11), 2341-2361.',
      'Supervised training improves balance and strength in older adults more than training alone.',
    ),
    'martinez_velilla2019': EvidenceSource(
      'Martínez-Velilla et al. (2019)',
      'Martínez-Velilla, N., Casas-Herrero, A., Zambom-Ferraresi, F., et al. (2019). Effect of exercise '
          'intervention on functional decline in very elderly patients during acute hospitalization: A '
          'randomized clinical trial. JAMA Internal Medicine, 179(1), 28-36.',
      'Short sessions (2 x 20 minutes a day) in hospital rehabilitation.',
    ),
    'mehta2024': EvidenceSource(
      'Mehta et al. (2024)',
      'Mehta, S. P., Karagiannopoulos, C., Pepin, M.-E., et al. (2024). Distal radius fracture rehabilitation: '
          'Clinical practice guidelines. Journal of Orthopaedic & Sports Physical Therapy, 54(9), CPG1-CPG78.',
      'After a cast: range of motion first, strengthening once the fracture is stable.',
    ),
    'otago2003': EvidenceSource(
      'Campbell & Robertson (2003)',
      'Campbell, A. J., & Robertson, M. C. (2003). Otago exercise programme to prevent falls in older adults. '
          'University of Otago Medical School; Accident Compensation Corporation.',
      'Home exercise dose (about 30 minutes, 10 repetitions), progression after two sets of 10, stop rules.',
    ),
    'sherrington2019': EvidenceSource(
      'Sherrington et al. (2019)',
      'Sherrington, C., Fairhall, N. J., Wallbank, G. K., et al. (2019). Exercise for preventing falls in older '
          'people living in the community. Cochrane Database of Systematic Reviews, CD012424.',
      'Balance and functional exercise reduce falls.',
    ),
    'vivifrail2019': EvidenceSource(
      'Izquierdo et al. (2019)',
      'Izquierdo, M., Casas-Herrero, A., Zambom-Ferraresi, F., Martínez-Velilla, N., Alonso-Bouzón, C., & '
          'Rodríguez-Mañas, L. (2019). Multi-component physical exercise program VIVIFRAIL: Prescription guide.',
      'Programmes for older adults start with a professional check; no strength training within a month of '
          'a fracture.',
    ),
    'who2020': EvidenceSource(
      'Bull et al. (2020)',
      'Bull, F. C., Al-Ansari, S. S., Biddle, S., et al. (2020). World Health Organization 2020 guidelines on '
          'physical activity and sedentary behaviour. British Journal of Sports Medicine, 54(24), 1451-1462.',
      'Strength and balance activity on several days a week for older adults.',
    ),
    'williams2007': EvidenceSource(
      'Williams et al. (2007)',
      'Williams, M. A., Haskell, W. L., Ades, P. A., et al. (2007). Resistance exercise in individuals with and '
          'without cardiovascular disease: 2007 update. Circulation, 116(5), 572-584.',
      'Strength exercise limits for heart conditions.',
    ),
  };

  /// In-text names for [keys], or [appRuleLabel] when there are none.
  static String cite(List<String> keys) {
    final known = [
      for (final k in keys)
        if (all[k] != null) all[k]!.short,
    ];
    return known.isEmpty ? appRuleLabel : known.join('; ');
  }
}
