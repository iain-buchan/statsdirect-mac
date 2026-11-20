import React from 'react';
import {statsDirectToolbar} from './toolbar-assets';
import './method-help.css';

export function MethodHelpButton({onClick}: {onClick: () => void}) {
  return <button type="button" className="method-help-button" data-command="methodHelp"
    title="Method help" aria-label="Method help" onClick={onClick}
    dangerouslySetInnerHTML={{__html: statsDirectToolbar.icon('help')}}/>;
}
