const SENSITIVE_NAME = [
  /(^|\/)\.ssh\//, /\.env($|\.)/, /\.credentials\.json$/, /\.(pem|key|p12|keystore)$/i,
  /(^|\/)\.aws\//, /(^|\/)\.gnupg\//, /id_(rsa|ed25519|ecdsa)/, /secrets?\.(ya?ml|json|toml)$/i,
  /\.kube\/config$/, /\.netrc$/,
];
const SECRET_CONTENT = [
  /-----BEGIN [A-Z ]*PRIVATE KEY-----/,
  /\bAKIA[0-9A-Z]{16}\b/,
  /\bsk-[A-Za-z0-9]{20,}\b/,
  /\bghp_[A-Za-z0-9]{20,}\b/,
  /\bBearer\s+eyJ[A-Za-z0-9_\-]{20,}/,
  /\bxox[baprs]-[A-Za-z0-9-]{10,}/,
];
// Brazilian PII (extra caution): CPF, CNPJ.
const PII_CONTENT = [/\b\d{3}\.\d{3}\.\d{3}-\d{2}\b/, /\b\d{2}\.\d{3}\.\d{3}\/\d{4}-\d{2}\b/];

export function isSensitivePath(p) {
  return SENSITIVE_NAME.some((re) => re.test(p));
}
export function scanContent(text) {
  for (const re of [...SECRET_CONTENT, ...PII_CONTENT]) {
    if (re.test(text)) return { flagged: true, rule: re.source };
  }
  return { flagged: false };
}
