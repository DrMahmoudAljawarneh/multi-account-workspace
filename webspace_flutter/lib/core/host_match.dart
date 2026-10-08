/// Heuristic registrable-domain matching used to decide whether the credential
/// auto-fill / save prompts are safe on the current page.
///
/// No public-suffix list is bundled; instead we take the last two labels and
/// keep a small list of common two-part public suffixes (co.uk, com.au, …) so
/// `mail.example.co.uk` and `accounts.example.co.uk` group under
/// `example.co.uk` instead of the useless `co.uk`.
const Set<String> _multiPartSuffixes = {
  'co.uk', 'org.uk', 'ac.uk', 'gov.uk', 'me.uk',
  'com.au', 'net.au', 'org.au', 'edu.au', 'gov.au',
  'co.nz', 'org.nz', 'net.nz',
  'co.in', 'firm.in', 'gen.in', 'ind.in',
  'com.br', 'net.br', 'org.br',
  'co.jp', 'ne.jp', 'or.jp',
  'com.cn', 'net.cn', 'org.cn',
  'com.sg', 'com.hk', 'com.tw', 'com.kr',
  'co.za', 'com.mx', 'com.tr', 'com.ar', 'com.sa', 'com.pl',
};

/// Reduces a hostname to its registrable (base) domain.
/// Returns `''` for empty input; falls back to the full host when two labels
/// are not enough to decide (e.g. `localhost`, bare domains).
String registrableDomain(String host) {
  var h = host.trim().toLowerCase();
  if (h.isEmpty) return '';
  while (h.endsWith('.')) {
    h = h.substring(0, h.length - 1);
  }
  if (h.isEmpty) return '';
  final labels = h.split('.');

  // IP addresses (v4 or a lone number): match exactly, never by suffix.
  final isNumeric = labels.every((l) => int.tryParse(l) != null);
  if (isNumeric) return h;

  if (labels.length <= 2) return h;
  final lastTwo = labels.sublist(labels.length - 2).join('.');
  if (_multiPartSuffixes.contains(lastTwo)) {
    if (labels.length <= 3) return h;
    return labels.sublist(labels.length - 3).join('.');
  }
  return lastTwo;
}

/// True when both hosts belong to the same (heuristic) registrable domain.
/// Empty hosts never match.
bool hostsMatch(String a, String b) {
  if (a.isEmpty || b.isEmpty) return false;
  final ra = registrableDomain(a);
  final rb = registrableDomain(b);
  return ra.isNotEmpty && ra == rb;
}
