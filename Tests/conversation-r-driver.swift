import Foundation

@main struct ConversationRTests {
    static var checks = 0
    static func check(_ ok: Bool,_ message: String) throws {
        guard ok else { throw ConversationRScript.Failure(message:message) }; checks += 1; print("PASS: " + message)
    }
    static func runR(_ code: String,_ name: String,_ assertions: String) throws {
        let folder=URL(fileURLWithPath:CommandLine.arguments[1]).appendingPathComponent(name)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let file=folder.appendingPathComponent("check.R"), log=folder.appendingPathComponent("output.txt")
        try (code + "\n" + assertions + "\ncat('STATSDIRECT_R_PASS\\n')\n").write(to:file,atomically:true,encoding:.utf8)
        FileManager.default.createFile(atPath:log.path,contents:nil)
        let handle=try FileHandle(forWritingTo:log); defer { try? handle.close() }
        let process=Process(); process.executableURL=URL(fileURLWithPath:CommandLine.arguments[2]); process.arguments=["--vanilla",file.path]
        process.currentDirectoryURL=folder; process.standardOutput=handle; process.standardError=handle
        try process.run(); process.waitUntilExit()
        let output=try String(contentsOf:log,encoding:.utf8)
        try check(process.terminationStatus==0 && output.contains("STATSDIRECT_R_PASS"),"real R executes \(name): " + (process.terminationStatus==0 ? "validated" : output))
    }
    static func main() {
        do { try run() } catch { print("FAIL: " + error.localizedDescription); exit(1) }
    }
    static func run() throws {
        let source="before <- c(312,242,340,388,296,254,391,402,290)\nafter <- c(300,201,232,312,220,256,328,330,231)"
        let example=try String(contentsOfFile:"Tests/ai-pefr.R",encoding:.utf8)
        let reply="Use the paired data.\n```r\nd <- before - after\n```\nThen analyse:\n```r\n" + example + "\n```"
        var messages=[["role":"user","text":"Explain pairing","rSource":source],["role":"assistant","text":reply]]
        let full=try ConversationRScript.build(messages,messageIndex:1)
        try runR(full,"pefr-full","stopifnot(length(d)==9, abs(unname(t.test(before,after,paired=TRUE)$statistic)-4.9257744860354)<1e-12, file.exists('Rplots.pdf'))")
        try check(full.contains("Nothing has been run automatically") && full.contains("running this script runs all included code"),"export labels source replay for review")
        let first=try ConversationRScript.build(messages,messageIndex:1,blockIndex:0)
        try runR(first,"first-block","stopifnot(length(d)==9, !exists('nonzero'), !file.exists('Rplots.pdf'))")
        messages.append(["role":"user","text":"Continue without sharing"])
        messages.append(["role":"assistant","text":"```r\nstopifnot(length(d)==9)\nprint(mean(d))\n```"])
        try runR(ConversationRScript.build(messages,messageIndex:3),"followup","stopifnot(length(before)==9)")
        messages.append(["role":"user","text":"Changed source","rSource":"before <- 999\nafter <- 1" ])
        messages.append(["role":"assistant","text":"```r\nlater_only <- TRUE\n```"])
        try check(try ConversationRScript.build(messages,messageIndex:1)==full,"older replies exclude later source edits and R code")
        let fresh=try ConversationRScript.build([["role":"assistant","text":"```r\nx <- 1\n```"]],messageIndex:0)
        try check(!fresh.contains("before <-") && !fresh.contains(".statsdirect_data"),"new conversations do not inherit old data")
        let user=try ConversationRScript.build([["role":"user","text":"```r\nx <- 5\n```"]],messageIndex:0)
        try runR(user,"user-code","stopifnot(x==5)")
        let mixed="```python\nprint('not R')\n```\n~~~~Rscript\nx <- 2\n~~~\nx <- 3\n~~~~\n```r\nunclosed"
        let blocks=ConversationRScript.blocks(mixed)
        try check(blocks.count==1 && blocks[0].code=="x <- 2\n~~~\nx <- 3","fence parser excludes other languages, shorter closers and unfinished blocks")
        let stepped=ConversationRScript.blocks("1. Take the differences:\n   ```r\n   d <- before - after\n     t.test(d)\n ok\n   ```\nDone.").map(\.code)
        try check(stepped==["d <- before - after\n  t.test(d)\nok"],"a block fenced under a list item loses the fence's indent and no more, as on Windows")
        for info in ["r", "R", "Rscript", "r title=\"Description\"", "rscript\tcaption=\"Example\"", "  R\tmore metadata  "] {
            let tagged=ConversationRScript.blocks("```" + info + "\nvalue <- 17\n```")
            try check(tagged.map(\.code)==["value <- 17"],"the first language word identifies a completed R block: " + info)
        }
        for info in ["", "python", "{r}", "{r echo=FALSE}", "r-extra", "rscripted", "r\u{00a0}metadata", "r title=`invalid`"] {
            try check(ConversationRScript.blocks("```" + info + "\nignored <- TRUE\n```").isEmpty,
                      "non-R language labels and invalid backtick info are excluded: " + info)
        }
        let orderedReply = """
        ```r
        first_value <- 2
        ```
        ```python
        ignored <- TRUE
        ```
        ~~~~Rscript title="Second block"
        second_value <- first_value + 3
        ~~~~
           ```R\tcaption="Third block"
           third_value <- second_value * 2
           ```
        ```r unfinished
        never_complete <- TRUE
        """
        let ordered=ConversationRScript.blocks(orderedReply)
        try check(ordered.map(\.code)==["first_value <- 2", "second_value <- first_value + 3", "third_value <- second_value * 2"],
                  "mixed metadata, fence characters and list indentation retain the three completed R blocks in order")
        let otherCloser=ConversationRScript.blocks("~~~~r title=`example`\nvalue <- 1\n```\n~~~~")
        try check(otherCloser.map(\.code)==["value <- 1\n```"],"metadata does not permit a different fence character to end a block")
        let replayMessages=[["role":"assistant","text":orderedReply]]
        let second=try ConversationRScript.build(replayMessages,messageIndex:0,blockIndex:1)
        try check(second.contains("first_value <- 2") && second.contains("second_value <- first_value + 3") && !second.contains("third_value <-"),
                  "selecting the metadata-bearing second block includes earlier R dependencies and excludes later blocks")
        try runR(ConversationRScript.build(replayMessages,messageIndex:0,blockIndex:2),"metadata-blocks",
                 "stopifnot(first_value==2, second_value==5, third_value==10, !exists('ignored'), !exists('never_complete'))")
        for index in [-2,9] { var rejected=false; do { _=try ConversationRScript.build(messages,messageIndex:1,blockIndex:index) } catch is ConversationRScript.Failure { rejected=true }; try check(rejected,"invalid block is rejected") }
        let special="quoted \"value\"\\path\nα\tline"
        let data:[String:Any]=["datasetId":"fixed-data","columns":[["index":7,"values":["1.5",NSNull(),"-2e1"]],["index":2,"values":[special,NSNull(),"x'); stop('INJECTED') #"]]]]
        let rData=try ConversationRScript.dataset(data)
        let worksheet=try ConversationRScript.build([["role":"assistant","rData":rData,"text":"```r\nnumbers <- .statsdirect_data[['fixed-data']][['column_7']]\nwords <- .statsdirect_data[['fixed-data']][['column_2']]\n```"]],messageIndex:0)
        try runR(worksheet,"worksheet","stopifnot(identical(numbers,c(1.5,NA,-20)), identical(words[1]," + (try ConversationRScript.quote(special)) + "), is.na(words[2]), length(words)==3)")
        try check(!rData.contains("column_0"),"worksheet aliases retain their actual column indices")
        var rejected=false; do { _=try ConversationRScript.quote("null\0text") } catch is ConversationRScript.Failure { rejected=true }; try check(rejected,"R-incompatible null character is rejected")
        rejected=false; do { _=try ConversationRScript.build([["role":"assistant","rSource":String(repeating:"x",count:2_000_001),"text":"```r\nx\n```"]],messageIndex:0) } catch is ConversationRScript.Failure { rejected=true }; try check(rejected,"oversized replay is rejected")
        let long=String(repeating:"# full local source\n",count:1000) + source
        try runR(ConversationRScript.build([["role":"user","text":"Long source","rSource":long],["role":"assistant","text":"```r\nd <- before-after\n```"]],messageIndex:1),"full-local-source","stopifnot(length(d)==9)")
        print("PASS: \(checks) conversation R checks, including seven fresh real-R executions")
    }
}
