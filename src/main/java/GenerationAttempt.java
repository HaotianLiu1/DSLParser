import java.util.List;

public class GenerationAttempt {
    public final int attempt;
    public final String dsl;
    public final List<String> errors;
    public final String dslPath;
    public final String logPath;

    public GenerationAttempt(int attempt, String dsl, List<String> errors, String dslPath, String logPath) {
        this.attempt = attempt;
        this.dsl = dsl;
        this.errors = errors;
        this.dslPath = dslPath;
        this.logPath = logPath;
    }
}
