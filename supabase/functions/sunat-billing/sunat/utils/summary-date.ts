export function peruDate(now = new Date()): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Lima", year: "numeric", month: "2-digit", day: "2-digit",
  }).format(now);
}

export function summaryId(generationDate: string, correlativo: string): string {
  return `RC-${generationDate.replaceAll("-", "")}-${correlativo}`;
}
