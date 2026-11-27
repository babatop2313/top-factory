package __BASE_PACKAGE__.config;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.junit.jupiter.api.Assertions.fail;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import java.util.TreeSet;
import java.util.concurrent.TimeUnit;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Stream;
import org.junit.jupiter.api.Assumptions;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;

/**
 * Kit Top Factory — socle des conventions, section « Configuration » : les fichiers .env (secrets) ne sont jamais
 * versionnés, .env.example (sans aucune valeur) l'est et déclare toutes les variables requises.
 * Sans Git disponible, les tests sont ignorés en local et échouent en CI (variable CI définie).
 */
class RepositorySecretsHygieneTest {

    private static final Path RESOURCES = Path.of("src/main/resources");
    private static final Pattern ENV_FILE = Pattern.compile("(^|/)\\.env(\\.[^/]+)?$");
    private static final Pattern REQUIRED_VARIABLE = Pattern.compile("\\$\\{([A-Z][A-Z0-9_]*)}");

    private static Path root;

    @BeforeAll
    static void racineDuDepot() {
        String top = git("rev-parse", "--show-toplevel");
        if (top == null) {
            if (System.getenv("CI") != null) {
                fail("Git est indispensable en CI pour vérifier que les .env ne sont pas versionnés.");
            }
            Assumptions.abort("Git indisponible : vérification des .env ignorée en local.");
        }
        root = Path.of(top.strip());
    }

    @Test
    void depot_quandOnListeLesFichiersSuivis_alorsAucunEnv() {
        List<String> tracked = new ArrayList<>();
        for (String file : git("ls-files").split("\\R")) {
            if (ENV_FILE.matcher(file).find() && !file.endsWith(".env.example")) {
                tracked.add(file);
            }
        }
        assertTrue(tracked.isEmpty(), "Fichiers .env suivis par Git (à retirer : git rm --cached) : " + tracked);
    }

    @Test
    void gitignore_quandOnLeVerifie_alorsEnvIgnoreEtEnvExampleVersionne() {
        assertEquals(0, gitStatus("check-ignore", "-q", "--no-index", ".env"), ".env n'est pas ignoré par .gitignore");
        assertEquals(0, gitStatus("check-ignore", "-q", "--no-index", "un-module/.env"), "un .env de sous-dossier n'est pas ignoré");
        assertEquals(1, gitStatus("check-ignore", "-q", "--no-index", ".env.example"), ".env.example ne doit pas être ignoré");
    }

    @Test
    void envExample_quandOnLeLit_alorsAucuneValeur() throws IOException {
        Path example = root.resolve(".env.example");
        assertTrue(Files.exists(example), ".env.example absent à la racine du dépôt");
        List<String> withValue = new ArrayList<>();
        List<String> lines = Files.readAllLines(example, StandardCharsets.UTF_8);
        for (int i = 0; i < lines.size(); i++) {
            String line = lines.get(i).strip();
            if (line.isEmpty() || line.startsWith("#")) continue;
            int eq = line.indexOf('=');
            if (eq < 0 || !line.substring(eq + 1).isBlank()) {
                withValue.add(".env.example:" + (i + 1) + " (" + (eq < 0 ? line : line.substring(0, eq)) + ")");
            }
        }
        assertTrue(withValue.isEmpty(), "Lignes de .env.example avec une valeur (seul NOM= est permis) : " + withValue);
    }

    @Test
    void envExample_quandOnLeCompareALaConfiguration_alorsToutesLesVariablesRequisesSontDeclarees() throws IOException {
        Set<String> declared = new TreeSet<>();
        for (String line : Files.readAllLines(root.resolve(".env.example"), StandardCharsets.UTF_8)) {
            String l = line.strip().replaceFirst("^#\\s*", "");
            int eq = l.indexOf('=');
            if (eq > 0) declared.add(l.substring(0, eq).strip());
        }
        Set<String> missing = new TreeSet<>();
        try (Stream<Path> files = Files.list(RESOURCES)) {
            for (Path f : files.filter(p -> p.getFileName().toString().matches("application.*\\.(ya?ml|properties)")).toList()) {
                Matcher m = REQUIRED_VARIABLE.matcher(Files.readString(f, StandardCharsets.UTF_8));
                while (m.find()) {
                    if (!declared.contains(m.group(1))) missing.add(m.group(1));
                }
            }
        }
        assertTrue(missing.isEmpty(), "Variables requises absentes de .env.example : " + missing);
    }

    private static String git(String... args) {
        try {
            Process p = new ProcessBuilder(command(args)).redirectErrorStream(false).start();
            String out = new String(p.getInputStream().readAllBytes(), StandardCharsets.UTF_8);
            return p.waitFor(30, TimeUnit.SECONDS) && p.exitValue() == 0 ? out : null;
        } catch (IOException e) {
            return null;
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return null;
        }
    }

    private static int gitStatus(String... args) {
        try {
            Process p = new ProcessBuilder(command(args)).start();
            p.getInputStream().readAllBytes();
            return p.waitFor(30, TimeUnit.SECONDS) ? p.exitValue() : -1;
        } catch (IOException e) {
            return -1;
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return -1;
        }
    }

    private static List<String> command(String... args) {
        List<String> cmd = new ArrayList<>();
        cmd.add("git");
        if (root != null) {
            cmd.add("-C");
            cmd.add(root.toString());
        }
        cmd.addAll(List.of(args));
        return cmd;
    }
}
