package org.ffido.imageqa;
import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.widget.TextView;
import org.json.JSONObject;
import java.io.InputStream;
import java.security.MessageDigest;

/** Separate, deliberately debuggable QA APK. Never included in FFIDO. */
public class ReceiverActivity extends Activity {
  private static android.os.ParcelFileDescriptor held;
  private String hash(InputStream stream) throws Exception {
    MessageDigest hash=MessageDigest.getInstance("SHA-256");
    byte[] chunk=new byte[4096];int n;
    while((n=stream.read(chunk))!=-1)hash.update(chunk,0,n);
    StringBuilder result=new StringBuilder();for(byte b:hash.digest())result.append(String.format("%02x",b));return result.toString();
  }
  private String hash(Uri uri) throws Exception {
    MessageDigest hash=MessageDigest.getInstance("SHA-256");
    try(InputStream stream=getContentResolver().openInputStream(uri)) {
      byte[] chunk=new byte[4096]; int n;
      while((n=stream.read(chunk))!=-1) hash.update(chunk,0,n);
    }
    StringBuilder result=new StringBuilder();for(byte b:hash.digest())result.append(String.format("%02x",b));return result.toString();
  }
  @Override public void onCreate(Bundle state) {
    super.onCreate(state);
    JSONObject report=new JSONObject();
    try {
      report.put("action",getIntent().getAction());
      if(Intent.ACTION_SEND.equals(getIntent().getAction())) {
        Uri uri=getIntent().getParcelableExtra(Intent.EXTRA_STREAM);
        report.put("uri",uri.toString());report.put("mime",getContentResolver().getType(uri));report.put("intentMime",getIntent().getType());report.put("writeGrant",(getIntent().getFlags() & Intent.FLAG_GRANT_WRITE_URI_PERMISSION)!=0);report.put("sha256",hash(uri));
        boolean writable=false;
        try { android.os.ParcelFileDescriptor fd=getContentResolver().openFileDescriptor(uri,"rw");if(fd!=null){writable=true;fd.close();} } catch(Exception expected) {}
        report.put("writable",writable);
        // Retain an open descriptor as a real receiver doing delayed I/O.
        // Activity-scoped URI grants are expected to end when that activity ends.
        if(held!=null) {
          try(InputStream previous=new java.io.FileInputStream(held.getFileDescriptor())) {report.put("previousSha256",hash(previous));}
          held.close();
        }
        held=getContentResolver().openFileDescriptor(uri,"r");
      }
    }catch(Exception error){try{report.put("error",error.toString());}catch(Exception ignored){}}
    try(java.io.FileOutputStream out=openFileOutput("result.json",0)){out.write(report.toString().getBytes(java.nio.charset.StandardCharsets.UTF_8));}catch(Exception ignored){}
    TextView view=new TextView(this);view.setText(report.toString());setContentView(view);
  }
}
