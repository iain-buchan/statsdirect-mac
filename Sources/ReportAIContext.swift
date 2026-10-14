import Foundation

/// Read only the rendered report after consent. Run records can contain source
/// paths and worksheet values that are not displayed; they never enter this snapshot.
@MainActor enum ReportAIContext {
    static func snapshot(viewer: Viewer, document: Document, resultID: String?) async throws -> [String:Any] {
        guard !document.web.isLoading else { throw ChatGPTTutor.Failure(message:"The report is still loading. Please try again.") }
        let title=String(document.title.prefix(200)), entries=document.reportEntries ?? []
        let requested=viewer.jsString(resultID ?? "")
        var value=try await viewer.learningJavaScript(document,#"""
        (()=>{
          const root=document.getElementById('report-results');
          if(!root)throw Error('The report is still loading. Please try again.');
          const entries=[...root.querySelectorAll('.report-entry')];
          const at=node=>{const el=node?.nodeType===1?node:node?.parentElement;const entry=el?.closest('.report-entry');return entry&&root.contains(entry)?entry:null;};
          const selected=entries.find(e=>e.dataset.resultId===\#(requested))||at(window.getSelection()?.anchorNode)||entries.at(-1);
          const text=root.innerText, focus=selected?.innerText||'';
          const charts=[...root.querySelectorAll('svg,img')].filter(e=>e.getClientRects().length&&getComputedStyle(e).visibility!=='hidden');
          const chartText=charts.map(e=>e.tagName.toLowerCase()==='svg'?[...e.querySelectorAll('text')].filter(t=>t.getClientRects().length&&getComputedStyle(t).visibility!=='hidden').map(t=>t.textContent).join(' '):(e.getAttribute('alt')||'')).join('\n');
          return {text:text.slice(0,18000),totalCharacters:text.length,textLimit:18000,truncated:text.length>18000,
            focusedResult:{id:selected?.dataset.resultId||'',text:focus.slice(0,6000),truncated:focus.length>6000},
            resultIDs:entries.slice(0,40).map(e=>e.dataset.resultId),resultCount:entries.length,resultsTruncated:entries.length>40,
            chartCount:charts.length,chartText:chartText.slice(0,2000),chartTextTruncated:chartText.length>2000,
            chartImagesIncluded:false,snapshot:true};
        })()
        """#)
        value["documentId"]=document.id;value["title"]=title;value["kind"]="report"
        let ids=value.removeValue(forKey:"resultIDs") as? [String] ?? []
        value["results"]=ids.compactMap { id -> [String:String]? in
            guard let entry=entries.first(where:{$0.id==id}) else { return nil }
            return ["id":id,"title":String(entry.title.prefix(200)),"operation":entry.operation]
        }
        if var focus=value["focusedResult"] as? [String:Any], let id=focus["id"] as? String,
           let entry=entries.first(where:{$0.id==id}) {
            focus["title"]=String(entry.title.prefix(200));focus["operation"]=entry.operation
            value["focusedResult"]=focus
        }
        value["scope"]="Displayed report text and chart labels only. No chart pixels, hidden run records, original worksheet values or source file paths are included unless they appear in the displayed report. The report may contain user edits."
        return value
    }
}
