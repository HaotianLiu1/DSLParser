import java.util.List;

public class ToolchainResult {
    public final String dsl;
    public final String logPath;
    public final String svgPath;
    public final List<String> errors;

    public ToolchainResult(String dsl, String logPath, String svgPath, List<String> errors) {
        this.dsl = dsl;
        this.logPath = logPath;
        this.svgPath = svgPath;
        this.errors = errors;
    }
}
