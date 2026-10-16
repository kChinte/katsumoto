import { describe, expect, it } from "vitest";
import { buildSummaryDocument } from "../../supabase/functions/sunat-billing/sunat/transformers";
import { buildSummaryXml } from "../../supabase/functions/sunat-billing/sunat/xml/templates/summary";
import { peruDate, summaryId } from "../../supabase/functions/sunat-billing/sunat/utils/summary-date";

describe("SUNAT summary dates", () => {
  it("uses the Peru calendar date around midnight", () => {
    expect(peruDate(new Date("2026-10-15T03:04:08Z"))).toBe("2026-10-14");
    expect(peruDate(new Date("2026-10-15T04:59:59Z"))).toBe("2026-10-14");
    expect(peruDate(new Date("2026-10-15T05:00:00Z"))).toBe("2026-10-15");
  });

  it("keeps the reference date separate from the generation date and file identifier", () => {
    const document = buildSummaryDocument([], "2026-10-13", 3, new Date("2026-10-15T03:04:08Z"));
    const xml = buildSummaryXml(document, { ruc: "20608183672", razon_social: "UNITED" });
    expect(xml).toContain("<cbc:ReferenceDate>2026-10-13</cbc:ReferenceDate>");
    expect(xml).toContain("<cbc:IssueDate>2026-10-14</cbc:IssueDate>");
    expect(xml).toContain(`<cbc:ID>${summaryId(document.fecha_generacion, document.correlativo)}</cbc:ID>`);
    expect(summaryId(document.fecha_generacion, document.correlativo)).toBe("RC-20261014-3");
  });
});
