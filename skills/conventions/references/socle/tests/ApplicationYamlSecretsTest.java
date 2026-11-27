package __BASE_PACKAGE__.config;

import static org.junit.jupiter.api.Assertions.assertTrue;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Deque;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Stream;
import org.junit.jupiter.api.Test;

/**
 * Kit Top Factory — socle des conventions, section « Configuration » : aucun secret dans la configuration.
 * <ul>
 *   <li>pas de valeur par défaut pour un secret : {@code ${DB_PASSWORD}}, jamais {@code ${DB_PASSWORD:postgres}} ;</li>
 *   <li>pas de secret écrit en clair ({@code password: postgres}) ;</li>
 *   <li>pas d'identifiant dans une URL ({@code redis://user:pass@hôte}, {@code ?password=…}).</li>
 * </ul>
 * Les messages citent le fichier, la ligne et la propriété, jamais la valeur.
 */
class ApplicationYamlSecretsTest {

    private static final Path RESOURCES = Path.of("src/main/resources");

    /** Noms (propriété ou variable) qui désignent un secret. */
    private static final Pattern SECRET_NAME = Pattern.compile(
            "(?i)(password|passwd|pwd|secret|token|credential|private[-_.]?key|api[-_.]?key|(^|[._-])key$)");

    /**
     * Propriétés au nom trompeur qui ne sont pas des secrets : nom exact, ou suffixe après un point.
     * Chaque entrée est commentée ; n'en ajouter qu'avec l'accord de l'humain.
     */
    private static final List<String> NOT_SECRETS = List.of(
            "token-validity-seconds" // durée de validité d'un jeton, pas le jeton
    );

    private static final Pattern PLACEHOLDER = Pattern.compile("\\$\\{([A-Za-z0-9_.-]+)(?::([^}]*))?}");
    private static final Pattern URL_CREDENTIALS = Pattern.compile(
            "://[^/\\s:@${}]+:[^@\\s/${}]+@|[?&](password|pwd|secret|token)=[^&\\s${]+", Pattern.CASE_INSENSITIVE);
    private static final Pattern YAML_ENTRY = Pattern.compile("^(\\s*)([A-Za-z0-9_.\\[\\]-]+)\\s*:\\s*(.*)$");

    @Test
    void configuration_quandOnLaParcourt_alorsAucunSecretNiValeurParDefautDeSecret() throws IOException {
        List<String> violations = new ArrayList<>();
        try (Stream<Path> files = Files.list(RESOURCES)) {
            files.filter(f -> f.getFileName().toString().matches("application.*\\.(ya?ml|properties)"))
                 .sorted()
                 .forEach(f -> violations.addAll(check(f)));
        }
        assertTrue(violations.isEmpty(), "Secrets dans la configuration :\n" + String.join("\n", violations));
    }

    private static List<String> check(Path file) {
        List<String> violations = new ArrayList<>();
        List<String> lines;
        try {
            lines = Files.readAllLines(file);
        } catch (IOException e) {
            throw new IllegalStateException("Lecture impossible : " + file, e);
        }
        boolean properties = file.toString().endsWith(".properties");
        Deque<int[]> indents = new ArrayDeque<>();
        Deque<String> keys = new ArrayDeque<>();
        for (int i = 0; i < lines.size(); i++) {
            String line = lines.get(i);
            String trimmed = line.strip();
            if (trimmed.isEmpty() || trimmed.startsWith("#") || trimmed.startsWith("!") || trimmed.startsWith("---")) {
                continue;
            }
            String key;
            String value;
            if (properties) {
                int eq = line.indexOf('=');
                if (eq < 0) continue;
                key = line.substring(0, eq).strip();
                value = line.substring(eq + 1).strip();
            } else {
                Matcher m = YAML_ENTRY.matcher(line.startsWith("- ") ? line.substring(2) : line);
                if (!m.matches()) {
                    value = trimmed.startsWith("- ") ? trimmed.substring(2) : trimmed;
                    checkUrl(file, i, String.join(".", keys), value, violations);
                    continue;
                }
                int indent = m.group(1).length();
                while (!indents.isEmpty() && indents.peek()[0] >= indent) {
                    indents.pop();
                    keys.removeLast();
                }
                indents.push(new int[] {indent});
                keys.addLast(m.group(2));
                key = String.join(".", keys);
                value = stripComment(m.group(3));
            }
            checkEntry(file, i, key, value, violations);
        }
        return violations;
    }

    private static void checkEntry(Path file, int line, String key, String value, List<String> violations) {
        if (value.isEmpty() || value.equals("|") || value.equals(">")) {
            return;
        }
        String where = file.getFileName() + ":" + (line + 1) + " (" + key + ")";
        Matcher p = PLACEHOLDER.matcher(value);
        boolean placeholder = false;
        while (p.find()) {
            placeholder = true;
            String variable = p.group(1);
            String byDefault = p.group(2);
            if (byDefault != null && !byDefault.isBlank() && (isSecret(key) || isSecret(variable))) {
                violations.add(where + " : valeur par défaut pour le secret ${" + variable + "} — à retirer");
            }
        }
        if (!placeholder && isSecret(key) && !value.equals("\"\"") && !value.equals("''")) {
            violations.add(where + " : secret écrit en clair — à remplacer par ${VARIABLE}");
        }
        checkUrl(file, line, key, value, violations);
    }

    private static void checkUrl(Path file, int line, String key, String value, List<String> violations) {
        if (URL_CREDENTIALS.matcher(value).find()) {
            violations.add(file.getFileName() + ":" + (line + 1) + " (" + key + ") : identifiant dans une URL — à passer en variables");
        }
    }

    private static boolean isSecret(String name) {
        String lower = name.toLowerCase();
        for (String exception : NOT_SECRETS) {
            if (lower.equals(exception) || lower.endsWith("." + exception)) {
                return false;
            }
        }
        String last = lower.substring(lower.lastIndexOf('.') + 1);
        return SECRET_NAME.matcher(last).find();
    }

    private static String stripComment(String value) {
        int hash = value.indexOf(" #");
        return (hash >= 0 ? value.substring(0, hash) : value).strip();
    }
}
