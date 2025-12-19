import java.util.List;

public class ParseResult {
    public final String logPath;
    public final String svgPath;
    public final List<String> errors;
    public final boolean success;

    public ParseResult(String logPath, String svgPath, List<String> errors, boolean success) {
        this.logPath = logPath;
        this.svgPath = svgPath;
        this.errors = errors;
        this.success = success;
    }
}
