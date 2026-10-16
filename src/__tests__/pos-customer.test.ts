import { afterEach, describe, expect, it, vi } from "vitest";
vi.mock("@/lib/supabase", () => ({ supabase: {}, getCurrentOrgId: vi.fn() }));
import { customerService } from "@/services/customer.service";
import type { Customer } from "@/lib/types";

afterEach(() => vi.restoreAllMocks());

describe("POS customer resolution", () => {
  it("loads the selected customer from the database even before the client list refreshes", async () => {
    const customer = { id: "new-client", document_type: "RUC", document_number: "20130200789", is_active: true } as Customer;
    const fetch = vi.spyOn(customerService, "getById").mockResolvedValue(customer);
    expect(await customerService.getInvoiceCustomer("new-client", "factura")).toBe(customer);
    expect(fetch).toHaveBeenCalledWith("new-client");
  });
  it("does not replace a missing selected customer with Consumidor Final", async () => {
    vi.spyOn(customerService, "getById").mockResolvedValue(null);
    await expect(customerService.getInvoiceCustomer("missing", "boleta")).rejects.toThrow("no esta disponible");
  });
  it("rejects Consumidor Final for a factura but permits it for a boleta", async () => {
    const customer = { document_type: "DNI", document_number: "00000000", is_active: true } as Customer;
    vi.spyOn(customerService, "getById").mockResolvedValue(customer);
    await expect(customerService.getInvoiceCustomer("default", "factura")).rejects.toThrow("RUC");
    expect(await customerService.getInvoiceCustomer("default", "boleta")).toBe(customer);
  });
});
