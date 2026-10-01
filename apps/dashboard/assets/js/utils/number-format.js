const MAGNITUDES = [
  [99, 'DuTg'],
  [96, 'UnTg'],
  [93, 'Tg'],
  [90, 'NoVg'],
  [87, 'OcVg'],
  [84, 'SpVg'],
  [81, 'SxVg'],
  [78, 'QiVg'],
  [75, 'QaVg'],
  [72, 'TrVg'],
  [69, 'DuVg'],
  [66, 'UnVg'],
  [63, 'Vg'],
  [60, 'NoDc'],
  [57, 'OcDc'],
  [54, 'SpDc'],
  [51, 'SxDc'],
  [48, 'QiDc'],
  [45, 'QaDc'],
  [42, 'Td'],
  [39, 'Dd'],
  [36, 'Ud'],
  [33, 'Dc'],
  [30, 'No'],
  [27, 'Oc'],
  [24, 'Sp'],
  [21, 'Sx'],
  [18, 'Qi'],
  [15, 'Qa'],
  [12, 'T'],
  [9, 'B'],
  [6, 'M'],
  [3, 'K'],
];

export function trimNumber(value) {
  return String(value)
    .replace(/\.0+$/, '')
    .replace(/(\.\d*[1-9])0+$/, '$1');
}

function numeric(value) {
  if (typeof value === 'number') return value;
  if (typeof value === 'string' && value.trim() !== '') return Number(value);
  return Number(value);
}

export function formatCompactNumber(value) {
  const n = numeric(value);
  if (!Number.isFinite(n)) return value == null ? '—' : String(value);

  const sign = n < 0 ? '-' : '';
  const abs = Math.abs(n);

  if (abs < 1000) {
    return sign + trimNumber(
      abs.toLocaleString(undefined, { maximumFractionDigits: 2 })
    );
  }

  const unit = MAGNITUDES.find(([power]) => abs >= 10 ** power);

  // This only occurs above our 10^99 table. Scientific is still a sane
  // fallback, but values through e+100 use the simulator suffixes above.
  if (!unit) {
    return sign + formatScientificNumber(abs);
  }

  const [power, suffix] = unit;
  const scaled = abs / (10 ** power);

  // Keep roughly three significant digits, matching simulator UIs:
  // 4.74SxDc, 10.2Ud, 119T, 999B.
  const decimals = scaled >= 100 ? 0 : scaled >= 10 ? 1 : 2;
  return `${sign}${trimNumber(scaled.toFixed(decimals))}${suffix}`;
}

export function formatScientificNumber(value) {
  const n = numeric(value);
  if (!Number.isFinite(n)) return value == null ? '—' : String(value);

  if (n === 0) return '0';

  const sign = n < 0 ? '-' : '';
  const [mantissa, exponentRaw] = Math.abs(n).toExponential(2).split('e');
  const exponent = exponentRaw.startsWith('+') || exponentRaw.startsWith('-')
    ? exponentRaw
    : `+${exponentRaw}`;

  return `${sign}${trimNumber(mantissa)}e${exponent}`;
}

export function formatMoney(value) {
  const n = numeric(value);
  if (!Number.isFinite(n)) return '—';

  const sign = n < 0 ? '-' : '';
  const abs = Math.abs(n);

  if (abs < 1000) {
    return `${sign}$${trimNumber(
      abs.toLocaleString(undefined, { maximumFractionDigits: 2 })
    )}`;
  }

  return `${sign}$${formatCompactNumber(abs)} / ${formatScientificNumber(abs)}`;
}
