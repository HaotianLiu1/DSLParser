import java.util.List;

public class ToolchainResult {
    public final boolean success;
    public final String dsl;
    public final String logPath;
    public final String svgPath;
    public final List<String> errors;
    public final List<GenerationAttempt> attempts;
    public final String failureReason;

    public ToolchainResult(boolean success,
                           String dsl,
                           String logPath,
                           String svgPath,
                           List<String> errors,
                           List<GenerationAttempt> attempts,
                           String failureReason) {
        this.success = success;
        this.dsl = dsl;
        this.logPath = logPath;
        this.svgPath = svgPath;
        this.errors = errors;
        this.attempts = attempts;
        this.failureReason = failureReason;
    }
}
