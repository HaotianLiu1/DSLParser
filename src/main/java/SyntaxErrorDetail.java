import org.antlr.v4.runtime.Token;

public class SyntaxErrorDetail {
    public final int line;
    public final int charPositionInLine;
    public final String offendingToken;
    public final String expectedTokens;
    public final String message;

    public SyntaxErrorDetail(int line, int charPositionInLine, String offendingToken, String expectedTokens, String message) {
        this.line = line;
        this.charPositionInLine = charPositionInLine;
        this.offendingToken = offendingToken;
        this.expectedTokens = expectedTokens;
        this.message = message;
    }

    public static SyntaxErrorDetail fromSyntaxError(int line, int charPositionInLine, Object offendingSymbol, String msg) {
        String tokenText = "";
        if (offendingSymbol instanceof Token token) {
            tokenText = token.getText();
        }
        String expected = "";
        if (msg != null) {
            int expectedIndex = msg.indexOf("expecting");
            if (expectedIndex >= 0) {
                expected = msg.substring(expectedIndex + "expecting".length()).trim();
            }
        }
        return new SyntaxErrorDetail(line, charPositionInLine, tokenText, expected, msg == null ? "" : msg);
    }

    public String toPromptLine() {
        return String.format("行 %d:%d, 错误 token: %s, 期待 token: %s", line, charPositionInLine, normalize(offendingToken), normalize(expectedTokens));
    }

    private String normalize(String value) {
        if (value == null || value.isBlank()) {
            return "(空)";
        }
        return value;
    }
}
