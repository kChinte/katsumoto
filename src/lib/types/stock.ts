// ---------- Stock Enums ----------
export type MovementType = "in" | "out" | "adjustment" | "transfer" | "transfer_out" | "transfer_in" | "return";

// ---------- Stock Movement ----------
export interface StockMovement {
  id: string;
  organization_id: string;
  product_id: string;
  branch_id: string;
  sale_branch_id: string | null;
  movement_type: MovementType;
  quantity: number;
  reference_type: string | null;
  reference_id: string | null;
  transfer_to_branch_id: string | null;
  source_channel: string | null;
  notes: string | null;
  created_by: string | null;
  created_at: string;
}
