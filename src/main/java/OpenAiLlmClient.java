import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;

public class OpenAiLlmClient implements LlmClient {
    private static final ObjectMapper MAPPER = new ObjectMapper();
    private static final String DEFAULT_API_BASE = "https://ark.cn-beijing.volces.com/api/v3";
    private static final String DEFAULT_MODEL = "deepseek-v3-2-251201";
    // 直接写死本地测试用的 Key，不建议提交到版本库
    private static final String DEFAULT_API_KEY = "f6b02c3d-8e22-45d9-a05d-5bf13d6ff2b9";

    private final HttpClient httpClient;
    private final String apiKey;
    private final String apiBase;
    private final String model;

    public OpenAiLlmClient() {
        this(HttpClient.newHttpClient(),
                readRequiredEnvOrDefault("OPENAI_API_KEY", DEFAULT_API_KEY),
                readOptionalEnv("OPENAI_API_BASE", DEFAULT_API_BASE),
                readOptionalEnv("OPENAI_MODEL", DEFAULT_MODEL));
    }

    public OpenAiLlmClient(HttpClient httpClient, String apiKey, String apiBase, String model) {
        this.httpClient = httpClient;
        this.apiKey = apiKey == null ? "" : apiKey.trim();
        this.apiBase = apiBase == null ? DEFAULT_API_BASE : apiBase.trim();
        this.model = model == null ? DEFAULT_MODEL : model.trim();
    }

    @Override
    public String generate(String prompt, String type) {
        ObjectNode payload = MAPPER.createObjectNode();
        payload.put("model", model);

        ArrayNode messages = payload.putArray("messages");
        ObjectNode system = messages.addObject();
        system.put("role", "system");
        system.put("content", "你是一个 DSL 生成助手，只输出 DSL 内容。");

        ObjectNode user = messages.addObject();
        user.put("role", "user");
        user.put("content", prompt);

        payload.put("temperature", 0.2);

        HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(apiBase + "/chat/completions"))
                .header("Authorization", "Bearer " + apiKey)
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(payload.toString(), StandardCharsets.UTF_8))
                .build();

        try {
            HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
            if (response.statusCode() >= 400) {
                throw new IllegalStateException("OpenAI 请求失败: " + response.statusCode() + " -> " + response.body());
            }
            JsonNode root = MAPPER.readTree(response.body());
            JsonNode content = root.at("/choices/0/message/content");
            if (content.isMissingNode() || content.asText().isBlank()) {
                throw new IllegalStateException("OpenAI 返回为空，请检查模型或配额。");
            }
            return content.asText().trim();
        } catch (IOException | InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("调用 OpenAI 失败: " + e.getMessage(), e);
        }
    }

    private static String readRequiredEnv(String name) {
        String value = System.getenv(name);
        if (value == null || value.isBlank()) {
            throw new IllegalStateException("缺少环境变量: " + name);
        }
        return value.trim();
    }

    private static String readOptionalEnv(String name, String defaultValue) {
        String value = System.getenv(name);
        if (value == null || value.isBlank()) {
            return defaultValue;
        }
        return value.trim();
    }

    private static String readRequiredEnvOrDefault(String name, String defaultValue) {
        String value = System.getenv(name);
        if (value != null && !value.isBlank()) {
            return value.trim();
        }
        if (defaultValue == null || defaultValue.isBlank()) {
            throw new IllegalStateException("缺少环境变量: " + name + "，且未在代码中设置默认值");
        }
        return defaultValue.trim();
    }
}
