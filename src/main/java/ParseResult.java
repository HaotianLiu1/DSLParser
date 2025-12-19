import java.util.List;

public class ParseResult {
    public final boolean success;
    public final List<String> errors;
    public final int errorCount;
    public final String logText;
    public final String visitorOutput;
    public final String dotPath;
    public final String svgPath;
    public final String logPath;

    public ParseResult(boolean success,
                       List<String> errors,
                       int errorCount,
                       String logText,
                       String visitorOutput,
                       String dotPath,
                       String svgPath,
                       String logPath) {
        this.success = success;
        this.errors = errors;
        this.errorCount = errorCount;
        this.logText = logText;
        this.visitorOutput = visitorOutput;
        this.dotPath = dotPath;
        this.svgPath = svgPath;
        this.logPath = logPath;
    }
}
