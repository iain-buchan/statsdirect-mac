import icons from '../Content/Mac/toolbar-icons.json';
import '../Content/Mac/toolbar.js';

const host = window as any;
host.StatsDirectToolbarIcons = icons;
export const statsDirectToolbar = host.StatsDirectToolbar;
