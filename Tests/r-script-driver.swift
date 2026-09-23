import Foundation
@main struct Driver {
    static func main() throws {
        let input = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let snapshot = try JSONSerialization.jsonObject(with: input) as! [String: Any]
        let plan = try RScriptGenerator.generate(operation: snapshot["operation"] as! String, title: snapshot["title"] as? String ?? "Test analysis", output: snapshot["output"] as! [String: Any], resources: URL(fileURLWithPath: CommandLine.arguments[2]))
        try plan.script.write(toFile: CommandLine.arguments[3], atomically: true, encoding: .utf8)
        print(plan.hasRecipe ? "recipe" : "starter")
    }
}
