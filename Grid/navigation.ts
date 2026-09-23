import { CompactSelection, type DataEditorRef, type GridSelection, type Item } from '@glideapps/glide-data-grid';

// Match Glide's in-cell Enter behaviour when editing through the value field.
export function selectCellBelow(cell: Item, rows: number, select: (selection: GridSelection) => void, grid: DataEditorRef | null) {
  const [col, row] = cell;
  const nextRow = Math.min(row + 1, rows - 1);
  select({
    columns: CompactSelection.empty(),
    rows: CompactSelection.empty(),
    current: { cell: [col, nextRow], range: { x: col, y: nextRow, width: 1, height: 1 }, rangeStack: [] }
  });
  requestAnimationFrame(() => {
    grid?.scrollTo(col, nextRow);
    grid?.focus();
  });
}
