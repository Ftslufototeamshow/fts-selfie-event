package lu.fts.printer;

import android.app.*;
import android.content.*;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.provider.Settings;
import android.widget.Toast;

import org.json.JSONObject;

import java.io.InputStream;
import java.security.MessageDigest;
import java.util.Locale;

final class AppUpdater {
    private AppUpdater() {}

    static void offer(Activity activity, JSONObject release) {
        if (release == null) return;
        int build = release.optInt("build_number", 0);
        if (build <= BuildConfig.VERSION_CODE) return;

        String version = release.optString("version", "neu");
        String notes = release.optString("notes", "");
        boolean mandatory = release.optBoolean("mandatory", false);
        String msg = "Installiert: " + BuildConfig.VERSION_NAME +
                "\nNeu: " + version +
                (notes.isEmpty() ? "" : "\n\n" + notes);

        AlertDialog.Builder b = new AlertDialog.Builder(activity)
                .setTitle("Neue FTS Printer Version verfügbar")
                .setMessage(msg)
                .setPositiveButton("Jetzt aktualisieren", (d,w) -> downloadAndInstall(activity, release));
        if (!mandatory) {
            b.setNegativeButton("Später", null);
        } else {
            b.setCancelable(false);
        }
        b.show();
    }

    static void downloadAndInstall(Activity activity, JSONObject release) {
        String url = release.optString("external_url", "");
        String expectedSha = release.optString("sha256", "").toLowerCase(Locale.ROOT).trim();
        String version = release.optString("version", "update").replaceAll("[^A-Za-z0-9._-]", "_");
        if (url.isEmpty()) {
            Toast.makeText(activity, "Update-Datei ist noch nicht veröffentlicht.", Toast.LENGTH_LONG).show();
            return;
        }
        if (expectedSha.isEmpty()) {
            Toast.makeText(activity, "Update wurde nicht installiert: SHA-256-Prüfsumme fehlt.", Toast.LENGTH_LONG).show();
            return;
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                !activity.getPackageManager().canRequestPackageInstalls()) {
            Intent settings = new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:" + activity.getPackageName()));
            activity.startActivity(settings);
            Toast.makeText(activity, "Bitte Installation für FTS Printer erlauben und danach „Jetzt aktualisieren“ erneut wählen.", Toast.LENGTH_LONG).show();
            return;
        }

        DownloadManager dm = (DownloadManager) activity.getSystemService(Context.DOWNLOAD_SERVICE);
        DownloadManager.Request req = new DownloadManager.Request(Uri.parse(url));
        req.setTitle("FTS Printer " + version);
        req.setDescription("Produktionsupdate wird geladen …");
        req.setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED);
        req.setDestinationInExternalFilesDir(activity, Environment.DIRECTORY_DOWNLOADS,
                "FTS-Printer-" + version + ".apk");
        long id = dm.enqueue(req);

        BroadcastReceiver receiver = new BroadcastReceiver() {
            @Override public void onReceive(Context context, Intent intent) {
                if (intent.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1) != id) return;
                try { activity.unregisterReceiver(this); } catch (Exception ignored) {}
                Uri uri = dm.getUriForDownloadedFile(id);
                if (uri == null) {
                    Toast.makeText(activity, "Update-Download fehlgeschlagen.", Toast.LENGTH_LONG).show();
                    return;
                }
                try {
                    String actual = sha256(activity, uri);
                    if (!expectedSha.equalsIgnoreCase(actual)) {
                        Toast.makeText(activity, "Update verworfen: Prüfsumme stimmt nicht.", Toast.LENGTH_LONG).show();
                        return;
                    }
                } catch (Exception e) {
                    Toast.makeText(activity, "Update konnte nicht geprüft werden: " + e.getMessage(), Toast.LENGTH_LONG).show();
                    return;
                }
                Intent install = new Intent(Intent.ACTION_VIEW);
                install.setDataAndType(uri, "application/vnd.android.package-archive");
                install.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_ACTIVITY_NEW_TASK);
                try {
                    activity.startActivity(install);
                } catch (Exception e) {
                    Toast.makeText(activity, "Android-Installer konnte nicht geöffnet werden.", Toast.LENGTH_LONG).show();
                }
            }
        };
        IntentFilter filter = new IntentFilter(DownloadManager.ACTION_DOWNLOAD_COMPLETE);
        if (Build.VERSION.SDK_INT >= 33) {
            activity.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED);
        } else {
            activity.registerReceiver(receiver, filter);
        }
    }

    private static String sha256(Context ctx, Uri uri) throws Exception {
        MessageDigest md = MessageDigest.getInstance("SHA-256");
        try (InputStream in = ctx.getContentResolver().openInputStream(uri)) {
            if (in == null) throw new IllegalStateException("Download nicht lesbar");
            byte[] buf = new byte[1024 * 1024];
            int n;
            while ((n = in.read(buf)) > 0) md.update(buf, 0, n);
        }
        StringBuilder out = new StringBuilder();
        for (byte b : md.digest()) out.append(String.format(Locale.ROOT, "%02x", b));
        return out.toString();
    }
}
