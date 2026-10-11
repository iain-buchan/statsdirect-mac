import { useEffect, useRef, type MouseEvent, type RefObject } from 'react';
import { CompactSelection, type DataEditorRef, type GridMouseEventArgs, type GridSelection, type Rectangle } from '@glideapps/glide-data-grid';

/** Extend Glide's header clicks with whole-column dragging. Cell dragging,
 * modifier clicks and edge resizing remain owned by Glide. */
export function useColumnDragSelection(grid: RefObject<DataEditorRef>, columnCount: number,
  select: (selection: GridSelection) => void, worksheet: object) {
  const visible = useRef({x: 0, width: 0});
  const drag = useRef<{anchor: number; end: number} | null>(null);
  const stop = () => { drag.current = null; };
  useEffect(() => {
    stop();
    const key = (event: KeyboardEvent) => { if (event.key === 'Escape') stop(); };
    window.addEventListener('mouseup', stop);
    window.addEventListener('blur', stop);
    window.addEventListener('keydown', key);
    return () => {
      stop();
      window.removeEventListener('mouseup', stop);
      window.removeEventListener('blur', stop);
      window.removeEventListener('keydown', key);
    };
  }, [worksheet, columnCount]);

  const onMouseDownCapture = (event: MouseEvent) => {
    stop();
    if (event.button !== 0 || event.shiftKey || event.metaKey || event.ctrlKey || event.altKey) return;
    // Only inspect visible headers, even in a worksheet with 16,384 columns.
    // getBounds uses viewport coordinates and accounts for scrolling/zoom.
    const first = Math.max(0, visible.current.x);
    const end = Math.min(columnCount, first + visible.current.width + 1);
    for (let column = first; column < end; column++) {
      const bounds = grid.current?.getBounds(column, -1);
      if (bounds && event.clientX >= bounds.x && event.clientX < bounds.x + bounds.width &&
          event.clientY >= bounds.y && event.clientY < bounds.y + bounds.height) {
        drag.current = {anchor: column, end: column};
        return;
      }
    }
  };
  const onItemHovered = (event: GridMouseEventArgs) => {
    if (!(event.buttons & 1)) { stop(); return; }
    const active = drag.current;
    if (!active || columnCount === 0) return;
    const end = Math.max(0, Math.min(columnCount - 1, event.location[0]));
    if (end === active.end) return;
    active.end = end;
    select({
      columns: CompactSelection.fromSingleSelection([Math.min(active.anchor, end), Math.max(active.anchor, end) + 1]),
      rows: CompactSelection.empty()
    });
  };
  return {
    onMouseDownCapture,
    onItemHovered, // Also receives Glide's updates while edge auto-scrolling.
    onVisibleRegionChanged: (region: Rectangle) => { visible.current = region; },
    onColumnResizeStart: stop
  };
}
