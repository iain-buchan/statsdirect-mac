import React from 'react';
import { CompactSelection, GridCellKind, isObjectEditorCallbackResult, numberCellRenderer, textCellRenderer,
  type DataEditorRef, type GridSelection, type Item, type GridCell, type ProvideEditorCallback, type ProvideEditorComponent } from '@glideapps/glide-data-grid';

type Movement = readonly [-1 | 0 | 1, -1 | 0 | 1];
const directions: Record<string, Movement> = { ArrowLeft: [-1, 0], ArrowRight: [1, 0], ArrowUp: [0, -1], ArrowDown: [0, 1], Enter: [0, 1] };
export function cellMovement(event: React.KeyboardEvent, includeEnter = true): Movement | undefined {
  if (event.nativeEvent.isComposing || event.shiftKey || event.altKey || event.ctrlKey || event.metaKey) return;
  if (!includeEnter && event.key === 'Enter') return;
  return directions[event.key];
}

// Keep the value field and in-cell editor consistent, without wrapping at an edge.
export function selectAdjacentCell(cell: Item, movement: Movement, columns: number, rows: number, select: (selection: GridSelection) => void, grid: DataEditorRef | null) {
  const [col, row] = cell;
  const nextCol = Math.max(0, Math.min(col + movement[0], columns - 1));
  const nextRow = Math.max(0, Math.min(row + movement[1], rows - 1));
  select({
    columns: CompactSelection.empty(),
    rows: CompactSelection.empty(),
    current: { cell: [nextCol, nextRow], range: { x: nextCol, y: nextRow, width: 1, height: 1 }, rangeStack: [] }
  });
  requestAnimationFrame(() => {
    grid?.scrollTo(nextCol, nextRow);
    grid?.focus();
  });
}

function withArrowNavigation<T extends GridCell>(provide: ProvideEditorCallback<T>): ProvideEditorCallback<T> {
  return cell => {
    const supplied = provide(cell);
    if (!supplied) return;
    const options = isObjectEditorCallbackResult(supplied) ? supplied : { editor: supplied };
    const Editor = options.editor;
    const NavigationEditor: ProvideEditorComponent<T> = props => <div onKeyDownCapture={event => {
      const movement = cellMovement(event, false);
      if (!movement) return;
      event.preventDefault();
      event.stopPropagation();
      props.onFinishedEditing(props.value, movement);
    }}><Editor {...props}/></div>;
    return { ...options, editor: NavigationEditor };
  };
}

const textEditor = withArrowNavigation(textCellRenderer.provideEditor!);
const numberEditor = withArrowNavigation(numberCellRenderer.provideEditor!);
// Retain Glide's parsing, formatting, validation, Tab and Escape behaviour.
export const arrowKeyEditor: ProvideEditorCallback<GridCell> = cell =>
  cell.kind === GridCellKind.Text ? textEditor(cell) : cell.kind === GridCellKind.Number ? numberEditor(cell) : undefined;
