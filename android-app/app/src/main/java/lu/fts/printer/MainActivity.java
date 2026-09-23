package lu.fts.printer;

import android.app.*;
import android.os.*;
import android.content.*;
import android.database.Cursor;
import android.graphics.*;
import android.graphics.pdf.PdfDocument;
import android.net.Uri;
import android.provider.OpenableColumns;
import android.print.*;
import android.print.pdf.PrintedPdfDocument;
import android.view.*;
import android.widget.*;
import android.text.InputType;
import android.text.method.PasswordTransformationMethod;
import android.graphics.drawable.GradientDrawable;

import org.json.*;

import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.text.SimpleDateFormat;
import java.util.*;
import java.util.concurrent.*;

public class MainActivity extends Activity {
    static final String SUPABASE = "https://hivmiqktbaatghuaxfvg.supabase.co";
    static final String KEY = "sb_publishable_ho0rkg5nbEhTpME_RPTdSA_UbzLRT9P";
    static final String BUCKET = "fts-selfie-live";

    final ExecutorService io = Executors.newFixedThreadPool(4);
    final Handler handler = new Handler(Looper.getMainLooper());
    final ArrayList<Staff> deviceAdmins = new ArrayList<>();
    final ArrayList<Staff> staff = new ArrayList<>();
    final ArrayList<EventModel> events = new ArrayList<>();
    final ArrayList<OrderModel> orders = new ArrayList<>();
    final ArrayList<JSONObject> workUnits = new ArrayList<>();
    final ArrayList<JSONObject> pickupRows = new ArrayList<>();
    final ArrayList<JSONObject> printerNodes = new ArrayList<>();
    final ArrayList<JSONObject> archiveRows = new ArrayList<>();

    SharedPreferences prefs;
    String deviceToken = "", sessionToken = "", currentUser = "", currentRole = "";
    String selectedEventToken = "";
    JSONObject stock = null;
    LinearLayout root, content;
    Spinner eventSpinner;
    TextView statusText, stockText, userText;
    boolean onMain = false;
    boolean recoveringAuth = false;
    String activeScreen = "orders";
    String pickupFilter = "";
    TextView eventInfoText;
    Uri selectedLocalPhoto = null;
    String selectedLocalName = null;

    @Override public void onCreate(Bundle b) {
        super.onCreate(b);
        prefs = getSharedPreferences("fts_printer", MODE_PRIVATE);
        deviceToken = prefs.getString("device_token","");
        sessionToken = prefs.getString("session_token","");
        buildBase();
        bootstrap();
    }

    @Override protected void onDestroy() {
        super.onDestroy();
        handler.removeCallbacksAndMessages(null);
        io.shutdownNow();
    }

    void buildBase() {
        root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(18), dp(18), dp(18), dp(12));
        root.setBackgroundColor(Color.rgb(7,23,25));

        TextView title = txt("FTS Printer", 28, Color.WHITE, true);
        root.addView(title);
        statusText = txt("Startet …", 12, Color.rgb(150,170,167), false);
        root.addView(statusText);

        ScrollView sv = new ScrollView(this);
        content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setPadding(0,dp(18),0,dp(30));
        sv.addView(content);
        root.addView(sv, new LinearLayout.LayoutParams(-1,0,1));
        setContentView(root);
    }

    void bootstrap() {
        if (deviceToken.isEmpty()) { loadDeviceAdmins(); return; }
        if (!sessionToken.isEmpty()) {
            rpc("fts_printer_validate_session_v72", obj(
                    "p_device_token",deviceToken,
                    "p_session_token",sessionToken
            ), result -> {
                if (result instanceof JSONObject && ((JSONObject)result).optBoolean("valid",false)) {
                    JSONObject o=(JSONObject)result;
                    currentUser=o.optString("display_name","");
                    currentRole=o.optString("role","employee");
                    showMain();
                    return;
                }
                sessionToken="";
                prefs.edit().remove("session_token").apply();
                loadStaff();
            });
        } else loadStaff();
    }

    void loadDeviceAdmins() {
        status("Printer-Administratoren werden geladen …");
        rpc("fts_printer_device_admin_choices_v75",obj(), result -> {
            deviceAdmins.clear();
            if(result instanceof JSONArray){
                JSONArray arr=(JSONArray)result;
                for(int i=0;i<arr.length();i++){
                    JSONObject o=arr.optJSONObject(i);if(o==null)continue;
                    deviceAdmins.add(new Staff(o.optString("user_id"),o.optString("display_name"),"printer_admin"));
                }
            }
            showDeviceSetup();
        });
    }

    void showDeviceSetup() {
        onMain=false; clear();
        addHeading("Samsung einmalig freischalten");
        addNote("Printer-Administrator auswählen und dessen persönlichen Printer-Code eingeben. Der alte globale FTS Admin-Code wird hier nicht mehr benötigt.");

        if(deviceAdmins.isEmpty()){
            content.addView(noteView("Kein aktiver Printer-Administrator gefunden. Im FTS Cockpit zuerst einen Printer-Administrator anlegen."));
            Button reload=button("Administratoren neu laden");
            content.addView(reload);
            reload.setOnClickListener(v->loadDeviceAdmins());
            return;
        }

        Spinner admins=new Spinner(this);
        ArrayList<String> names=new ArrayList<>();
        for(Staff s:deviceAdmins)names.add(s.name+" · Printer-Administrator");
        admins.setAdapter(new ArrayAdapter<>(this,android.R.layout.simple_spinner_dropdown_item,names));

        EditText code=input("Persönlicher Administrator-Code", true);
        code.setInputType(InputType.TYPE_CLASS_NUMBER|InputType.TYPE_NUMBER_VARIATION_PASSWORD);
        Button go=button("Samsung freischalten");
        Button reload=secondaryButton("Administratoren aktualisieren");
        content.addView(admins);content.addView(space(8));content.addView(code);content.addView(go);content.addView(reload);

        go.setOnClickListener(v -> {
            int pos=admins.getSelectedItemPosition();
            if(pos<0||pos>=deviceAdmins.size()){toast("Printer-Administrator auswählen.");return;}
            Staff admin=deviceAdmins.get(pos);
            String c=code.getText().toString().trim();
            if(c.isEmpty()){toast("Persönlichen Administrator-Code eingeben.");return;}
            go.setEnabled(false);
            rpc("fts_printer_register_device_v75",obj(
                    "p_user_id",admin.id,
                    "p_code",c,
                    "p_label","FTS Printer · Samsung Android",
                    "p_user_agent","FTS Printer Android 0.1.3"
            ), result -> {
                go.setEnabled(true);
                if(result instanceof String){
                    deviceToken=(String)result;
                    prefs.edit().putString("device_token",deviceToken).apply();
                    loadStaff();
                } else toast("Gerätefreigabe konnte nicht gespeichert werden.");
            });
        });
        reload.setOnClickListener(v->loadDeviceAdmins());
    }

    void loadStaff() {
        if(deviceToken.isEmpty()){showDeviceSetup();return;}
        status("Mitarbeiter werden geladen …");
        rpc("fts_printer_login_choices_v72",obj("p_device_token",deviceToken), result -> {
            if(!(result instanceof JSONArray)){deviceToken="";prefs.edit().remove("device_token").apply();loadDeviceAdmins();return;}
            staff.clear();
            JSONArray a=(JSONArray)result;
            for(int i=0;i<a.length();i++){
                JSONObject o=a.optJSONObject(i); if(o==null)continue;
                staff.add(new Staff(o.optString("user_id"),o.optString("display_name"),o.optString("role","employee")));
            }
            showLogin();
        });
    }

    void showLogin() {
        onMain=false; clear();
        addHeading("Wer arbeitet am Printer?");
        addNote("Mitarbeiter auswählen und persönlichen Code eingeben. Jeder Druck wird dieser Person zugeordnet.");
        Spinner sp=new Spinner(this);
        ArrayList<String> labels=new ArrayList<>();
        for(Staff s:staff)labels.add(s.name+" · "+(s.role.equals("printer_admin")?"Printer-Administrator":"Mitarbeiter"));
        ArrayAdapter<String> ad=new ArrayAdapter<>(this,android.R.layout.simple_spinner_dropdown_item,labels);
        sp.setAdapter(ad);
        EditText pin=input("Persönlicher Code",true);
        pin.setInputType(InputType.TYPE_CLASS_NUMBER|InputType.TYPE_NUMBER_VARIATION_PASSWORD);
        pin.setTransformationMethod(PasswordTransformationMethod.getInstance());
        Button login=button("Anmelden");
        Button refresh=secondaryButton("Liste aktualisieren");
        Button reset=secondaryButton("Gerätefreigabe zurücksetzen");
        content.addView(sp);content.addView(space(8));content.addView(pin);content.addView(login);content.addView(refresh);content.addView(reset);

        login.setOnClickListener(v -> {
            if(staff.isEmpty()){toast("Noch keine Mitarbeiter angelegt.");return;}
            Staff s=staff.get(sp.getSelectedItemPosition());
            String code=pin.getText().toString().trim();
            if(code.isEmpty()){toast("Code eingeben.");return;}
            login.setEnabled(false);
            rpc("fts_printer_login_v72",obj(
                    "p_device_token",deviceToken,
                    "p_user_id",s.id,
                    "p_code",code,
                    "p_device_label","FTS Printer · Samsung Android",
                    "p_user_agent","FTS Printer Android 0.1.3"
            ), result -> {
                login.setEnabled(true);
                if(result instanceof JSONObject){
                    JSONObject o=(JSONObject)result;
                    sessionToken=o.optString("session_token","");
                    currentUser=o.optString("display_name",s.name);
                    currentRole=o.optString("role",s.role);
                    prefs.edit().putString("session_token",sessionToken).apply();
                    showMain();
                }
            });
        });
        refresh.setOnClickListener(v->loadStaff());
        reset.setOnClickListener(v->{
            prefs.edit().clear().apply();deviceToken="";sessionToken="";loadDeviceAdmins();
        });
    }

    void showMain() {
        onMain=true; activeScreen="orders"; clear();
        LinearLayout top=row();
        LinearLayout left=new LinearLayout(this);left.setOrientation(LinearLayout.VERTICAL);
        userText=txt("FTS Printer",22,Color.WHITE,true);
        TextView sub=txt(currentUser+" · "+(currentRole.equals("printer_admin")?"Printer-Administrator":"Mitarbeiter"),12,Color.rgb(150,170,167),false);
        left.addView(userText);left.addView(sub);
        top.addView(left,new LinearLayout.LayoutParams(0,-2,1));
        Button switcher=secondaryButton("Mitarbeiter wechseln");
        top.addView(switcher);
        content.addView(top);
        switcher.setOnClickListener(v->logoutAndSwitch());

        addNote("Die App zeigt nur Printer-Funktionen. Firmenbuchhaltung und Umsätze anderer Events sind nicht freigegeben.");
        Button reloadEvents=secondaryButton("Events neu laden");
        content.addView(reloadEvents);

        eventSpinner=new Spinner(this);
        eventSpinner.setPopupBackgroundResource(android.R.color.white);
        content.addView(eventSpinner);
        eventInfoText=txt("Event wird geladen …",14,Color.WHITE,true);
        eventInfoText.setPadding(0,dp(4),0,dp(8));
        content.addView(eventInfoText);
        eventSpinner.setOnItemSelectedListener(new android.widget.AdapterView.OnItemSelectedListener(){
            public void onNothingSelected(android.widget.AdapterView<?> p){}
            public void onItemSelected(android.widget.AdapterView<?> p,View v,int pos,long id){
                if(pos>=0 && pos<events.size()){
                    EventModel e=events.get(pos);
                    selectedEventToken=e.token;
                    eventInfoText.setText(e.title+(e.location.isEmpty()?"":" · "+e.location)+(e.date.isEmpty()?"":" · "+e.date));
                    refreshSelected();
                }
            }
        });

        LinearLayout stockRow=row();
        stockText=txt("Bestand —",16,Color.WHITE,true);
        stockRow.addView(stockText,new LinearLayout.LayoutParams(0,-2,1));
        Button stockBtn=button("Bestand");
        stockRow.addView(stockBtn);
        content.addView(stockRow);
        stockBtn.setOnClickListener(v->showStockDialog());
        reloadEvents.setOnClickListener(v->{View b=findTagged(content,"body");if(b instanceof LinearLayout)loadEvents((LinearLayout)b);});

        LinearLayout tab=row();
        Button ordersBtn=button("Druckaufträge");
        Button pickupBtn=secondaryButton("Abholung");
        Button printersBtn=secondaryButton("Printer");
        Button cameraBtn=secondaryButton("Handyfoto");
        tab.addView(ordersBtn,new LinearLayout.LayoutParams(0,-2,1));
        tab.addView(pickupBtn,new LinearLayout.LayoutParams(0,-2,1));
        tab.addView(printersBtn,new LinearLayout.LayoutParams(0,-2,1));
        tab.addView(cameraBtn,new LinearLayout.LayoutParams(0,-2,1));
        content.addView(tab);

        LinearLayout body=new LinearLayout(this);body.setOrientation(LinearLayout.VERTICAL);body.setTag("body");
        content.addView(body);
        ordersBtn.setOnClickListener(v->{activeScreen="orders";renderOrders(body);});
        pickupBtn.setOnClickListener(v->{activeScreen="pickup";renderPickups(body,"");});
        printersBtn.setOnClickListener(v->{activeScreen="printers";renderPrinters(body);});
        cameraBtn.setOnClickListener(v->{activeScreen="camera";renderCamera(body);});

        loadEvents(body);
        checkUpdate();
        handler.removeCallbacksAndMessages(null);
        handler.postDelayed(new Runnable(){public void run(){if(onMain){refreshSelected();handler.postDelayed(this,5000);}}},5000);
    }

    void loadEvents(LinearLayout body) {
        status("Events werden geladen …");
        rpc("fts_printer_events_v74",obj("p_device_token",deviceToken,"p_session_token",sessionToken), result -> {
            if(!(result instanceof JSONArray))return;
            events.clear();
            JSONArray a=(JSONArray)result;
            for(int i=0;i<a.length();i++){
                JSONObject o=a.optJSONObject(i);if(o==null)continue;
                events.add(new EventModel(
                        o.optString("event_token"),o.optString("short_code"),o.optString("event_title"),
                        o.optString("location"),o.optString("event_date"),o.optBoolean("print_window_active",false),
                        o.optBoolean("local_camera_photos",false)
                ));
            }
            ArrayList<String> labels=new ArrayList<>();
            for(EventModel e:events)labels.add(e.title+(e.date.isEmpty()?"":" · "+e.date));
            ArrayAdapter<String> eventAdapter=new ArrayAdapter<String>(this,android.R.layout.simple_spinner_item,labels){
                @Override public View getView(int position,View convertView,android.view.ViewGroup parent){
                    TextView v=(TextView)super.getView(position,convertView,parent);
                    v.setTextColor(Color.WHITE);v.setTextSize(15);v.setPadding(dp(8),dp(10),dp(8),dp(10));
                    return v;
                }
                @Override public View getDropDownView(int position,View convertView,android.view.ViewGroup parent){
                    TextView v=(TextView)super.getDropDownView(position,convertView,parent);
                    v.setTextColor(Color.BLACK);v.setBackgroundColor(Color.WHITE);v.setPadding(dp(12),dp(12),dp(12),dp(12));
                    return v;
                }
            };
            eventAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item);
            eventSpinner.setAdapter(eventAdapter);
            if(events.isEmpty()){
                selectedEventToken="";
                eventInfoText.setText("Kein freigegebenes Printer-Event gefunden.");
                body.removeAllViews();
                body.addView(noteView("Kein Printer-Event freigegeben. Mit „Aktualisieren“ erneut laden."));
                Button retry=button("Events neu laden");body.addView(retry);retry.setOnClickListener(v->loadEvents(body));
                return;
            }
            int selectedIndex=0;
            for(int i=0;i<events.size();i++)if(events.get(i).token.equals(selectedEventToken)){selectedIndex=i;break;}
            selectedEventToken=events.get(selectedIndex).token;
            eventSpinner.setSelection(selectedIndex,false);
            EventModel current=events.get(selectedIndex);
            eventInfoText.setText(current.title+(current.location.isEmpty()?"":" · "+current.location)+(current.date.isEmpty()?"":" · "+current.date));
            refreshSelected();
            renderActive(body);
        });
    }

    void refreshSelected() {
        if(selectedEventToken.isEmpty()||deviceToken.isEmpty()||sessionToken.isEmpty())return;
        rpc("fts_printer_stock_v73",obj("p_device_token",deviceToken,"p_session_token",sessionToken,"p_event_token",selectedEventToken), result -> {
            if(result instanceof JSONObject){
                stock=(JSONObject)result;
                int available=stock.optInt("safe_available",0);
                int cameraWaiting=stock.optInt("camera_waiting",0);
                stockText.setText("Bestand: "+available+" sicher"+(cameraWaiting>0?" · Kamera wartet "+cameraWaiting:""));
                stockText.setTextColor(available<=0?Color.rgb(255,120,120):Color.WHITE);
            }
        });
        rpc("fts_printer_orders_v73",obj("p_device_token",deviceToken,"p_session_token",sessionToken,"p_event_token",selectedEventToken), result -> {
            if(!(result instanceof JSONArray))return;
            orders.clear(); JSONArray a=(JSONArray)result;
            for(int i=0;i<a.length();i++){JSONObject o=a.optJSONObject(i);if(o!=null)orders.add(new OrderModel(o));}
            renderActiveBody();
            status("Aktuell · "+new SimpleDateFormat("HH:mm",Locale.GERMANY).format(new Date()));
        });
        rpc("fts_printer_queue_v80",obj("p_device_token",deviceToken,"p_session_token",sessionToken,"p_event_token",selectedEventToken), result -> {
            if(result instanceof JSONArray){
                workUnits.clear();JSONArray a=(JSONArray)result;
                for(int i=0;i<a.length();i++){JSONObject o=a.optJSONObject(i);if(o!=null)workUnits.add(o);}
                renderActiveBody();
            }
        });
        rpc("fts_printer_pickups_v80",obj("p_device_token",deviceToken,"p_session_token",sessionToken,"p_event_token",selectedEventToken), result -> {
            if(result instanceof JSONArray){
                pickupRows.clear();JSONArray a=(JSONArray)result;
                for(int i=0;i<a.length();i++){JSONObject o=a.optJSONObject(i);if(o!=null)pickupRows.add(o);}
                renderActiveBody();
            }
        });
        rpc("fts_printer_nodes_v80",obj("p_device_token",deviceToken,"p_session_token",sessionToken,"p_event_token",selectedEventToken), result -> {
            if(result instanceof JSONArray){
                printerNodes.clear();JSONArray a=(JSONArray)result;
                for(int i=0;i<a.length();i++){JSONObject o=a.optJSONObject(i);if(o!=null)printerNodes.add(o);}
                renderActiveBody();
            }
        });
        rpc("fts_printer_archived_v80",obj("p_device_token",deviceToken,"p_session_token",sessionToken,"p_event_token",selectedEventToken,"p_limit",100), result -> {
            if(result instanceof JSONArray){
                archiveRows.clear();JSONArray a=(JSONArray)result;
                for(int i=0;i<a.length();i++){JSONObject o=a.optJSONObject(i);if(o!=null)archiveRows.add(o);}
                renderActiveBody();
            }
        });
    }

    void renderActiveBody(){
        View b=findTagged(content,"body");
        if(b instanceof LinearLayout)renderActive((LinearLayout)b);
    }

    void renderActive(LinearLayout body){
        if("camera".equals(activeScreen))renderCamera(body);
        else if("pickup".equals(activeScreen))renderPickups(body,pickupFilter);
        else if("printers".equals(activeScreen))renderPrinters(body);
        else renderOrders(body);
    }

    void renderOrders(LinearLayout body) {
        activeScreen="orders";
        body.removeAllViews();
        TextView h=txt("Automatische Druckaufträge",20,Color.WHITE,true);body.addView(h);
        body.addView(noteView("Der Mac-Print-Host verteilt jedes bezahlte Exemplar automatisch auf den nächsten freien Drucker. Das Samsung löst keinen zweiten Druck aus."));
        if(orders.isEmpty()){body.addView(noteView("Keine aktuellen Druckaufträge."));return;}
        for(OrderModel o:orders) body.addView(orderCard(o));
    }

    View orderCard(OrderModel o) {
        LinearLayout card=card();
        int totalUnits=0, printedUnits=0, uncertainUnits=0;
        ArrayList<JSONObject> uncertain=new ArrayList<>();
        for(JSONObject u:workUnits){
            if(!o.id.equals(u.optString("order_id")))continue;
            totalUnits++;
            String us=u.optString("unit_status");
            if("PRINTED".equals(us))printedUnits++;
            if("UNCERTAIN".equals(us)){uncertainUnits++;uncertain.add(u);}
        }

        String top;
        int topColor=Color.rgb(180,190,188);
        if("PRINTED".equalsIgnoreCase(o.printStatus)&&"READY_FOR_PICKUP".equalsIgnoreCase(o.pickupStatus)){
            top="ABHOLBEREIT";topColor=Color.rgb(80,220,140);
        } else if(uncertainUnits>0){
            top="PRÜFEN";topColor=Color.rgb(255,180,60);
        } else if(o.ready){
            top="IN WARTESCHLANGE";topColor=Color.rgb(80,220,140);
        } else top=safe(o.printStatus,"—");

        card.addView(txt(top,12,topColor,true));
        card.addView(txt("Abholcode "+safe(o.pickupCode,"------"),24,Color.WHITE,true));
        card.addView(txt((o.qty)+" × 10×15 · Zahlung "+safe(o.paymentStatus,"—"),14,Color.rgb(170,185,182),false));
        if(totalUnits>0)card.addView(txt("Druckfortschritt: "+printedUnits+"/"+totalUnits,14,Color.rgb(190,205,202),true));
        if(o.test)card.addView(txt("TEST / SANDBOX",12,Color.rgb(255,190,70),true));

        if(o.firstPath!=null&&!o.firstPath.isEmpty()){
            ImageView img=new ImageView(this);img.setAdjustViewBounds(true);img.setScaleType(ImageView.ScaleType.CENTER_CROP);
            img.setMinimumHeight(dp(160));card.addView(img,new LinearLayout.LayoutParams(-1,dp(180)));
            loadImage(o.firstPath,img);
        }

        for(JSONObject u:uncertain){
            LinearLayout warn=row();
            warn.addView(txt("Status unklar · Exemplar "+u.optInt("copy_index",1),12,Color.rgb(255,190,70),true),new LinearLayout.LayoutParams(0,-2,1));
            Button retry=secondaryButton("Nicht gedruckt · erneut");
            warn.addView(retry);
            retry.setOnClickListener(v->requeueUncertain(u));
            card.addView(warn);
        }

        LinearLayout buttons=row();
        if(o.receiptNumber!=null&&!o.receiptNumber.isEmpty()){
            Button receipt=secondaryButton("Beleg für Kunden");buttons.addView(receipt);receipt.setOnClickListener(v->showReceipt(o));
        }
        if("PRINTED".equalsIgnoreCase(o.printStatus)&&"READY_FOR_PICKUP".equalsIgnoreCase(o.pickupStatus)){
            Button openPickup=button("Zur Abholung");buttons.addView(openPickup);
            openPickup.setOnClickListener(v->{activeScreen="pickup";pickupFilter=safe(o.pickupCode,"");renderPickups((LinearLayout)findTagged(content,"body"),pickupFilter);});
        }
        card.addView(buttons);
        return card;
    }

    void requeueUncertain(JSONObject unit){
        String unitId=unit.optString("unit_id","");
        if(unitId.isEmpty())return;
        new AlertDialog.Builder(this).setTitle("Druck wirklich nicht erfolgt?")
                .setMessage("Nur erneut freigeben, wenn am Drucker geprüft wurde, dass dieses Exemplar NICHT herausgekommen ist. Sonst entsteht ein Doppelprint.")
                .setNegativeButton("Abbrechen",null)
                .setPositiveButton("Nicht gedruckt · erneut",(d,w)->rpc("fts_printer_fail_unit_v80",obj(
                        "p_device_token",deviceToken,"p_session_token",sessionToken,"p_unit_id",unitId,
                        "p_error","Samsung: Mitarbeiter bestätigt nicht gedruckt","p_confirm_not_printed",true
                ),r->{toast("Exemplar wieder freigegeben.");refreshSelected();}))
                .show();
    }

    void renderPickups(LinearLayout body,String filter){
        activeScreen="pickup";
        pickupFilter=filter==null?"":filter;
        body.removeAllViews();
        body.addView(txt("Kundenabholung",20,Color.WHITE,true));
        body.addView(noteView(pickupRows.size()+" Auftrag"+(pickupRows.size()==1?"":"e")+" warten auf Abholung."));

        LinearLayout searchRow=row();
        EditText search=input("Abholcode / A001 / B002",false);search.setText(pickupFilter);
        Button go=button("Suchen");
        searchRow.addView(search,new LinearLayout.LayoutParams(0,dp(52),1));searchRow.addView(go);
        body.addView(searchRow);
        go.setOnClickListener(v->{pickupFilter=search.getText().toString().trim();renderPickups(body,pickupFilter);});

        String q=pickupFilter.toUpperCase(Locale.ROOT);
        int shown=0;
        for(JSONObject p:pickupRows){
            String code=p.optString("customer_code","");
            if(!q.isEmpty()&&!code.toUpperCase(Locale.ROOT).contains(q))continue;
            shown++;
            LinearLayout card=card();
            card.addView(txt(code,26,Color.WHITE,true));
            String kind=p.optString("kind","SELFIE");
            int qty=p.optInt("quantity",0);
            card.addView(txt(kind+" · "+qty+" Ausdruck"+(qty==1?"":"e"),13,Color.rgb(170,185,182),false));
            LinearLayout actions=row();
            if("SELFIE".equalsIgnoreCase(kind)){
                OrderModel found=null;
                String id=p.optString("id","");
                for(OrderModel o:orders)if(o.id.equals(id)){found=o;break;}
                if(found!=null&&found.receiptNumber!=null&&!found.receiptNumber.isEmpty()){
                    OrderModel receiptOrder=found;
                    Button receipt=secondaryButton("Beleg für Kunden");actions.addView(receipt);receipt.setOnClickListener(v->showReceipt(receiptOrder));
                }
            }
            Button done=button("Foto abgeholt");actions.addView(done);
            done.setOnClickListener(v->markPickupRow(p));
            card.addView(actions);
            body.addView(card);
        }
        if(shown==0)body.addView(noteView("Keine passende Abholung gefunden."));
        body.addView(txt("Archiv · "+archiveRows.size(),16,Color.WHITE,true));
        int n=Math.min(20,archiveRows.size());
        for(int i=0;i<n;i++){
            JSONObject a=archiveRows.get(i);
            body.addView(txt(a.optString("customer_code","—")+" · "+a.optString("kind","")+" · "+a.optInt("quantity",0)+" ×",12,Color.rgb(150,170,167),false));
        }
    }

    void markPickupRow(JSONObject p){
        String kind=p.optString("kind","SELFIE");
        String id=p.optString("id","");
        String rpcName="LOCAL".equalsIgnoreCase(kind)?"fts_printer_mark_local_picked_up_archive_v80":"fts_printer_mark_picked_up_archive_v80";
        JSONObject args="LOCAL".equalsIgnoreCase(kind)
                ?obj("p_device_token",deviceToken,"p_session_token",sessionToken,"p_local_job_id",id)
                :obj("p_device_token",deviceToken,"p_session_token",sessionToken,"p_order_id",id);
        rpc(rpcName,args,r->{toast(Boolean.TRUE.equals(r)?"Abgeholt und archiviert.":"Auftrag ist nicht abholbereit.");pickupFilter="";refreshSelected();});
    }

    void renderPrinters(LinearLayout body){
        activeScreen="printers";
        body.removeAllViews();
        body.addView(txt("Printer-Aktivität",20,Color.WHITE,true));
        body.addView(noteView("Die physischen Druckjobs werden vom Mac-Print-Host parallel auf die freigegebenen Drucker verteilt."));
        if(printerNodes.isEmpty()){body.addView(noteView("Noch kein aktiver Mac-Printer gemeldet."));return;}
        for(JSONObject n:printerNodes){
            LinearLayout card=card();
            card.addView(txt(n.optString("display_name",n.optString("printer_key","Printer")),18,Color.WHITE,true));
            String st=n.optString("state","—");
            int eta=n.optInt("eta_seconds",0);
            card.addView(txt(st+(eta>0?" · ca. "+eta+" Sek.":""),14,"ERROR".equals(st)?Color.rgb(255,120,120):Color.rgb(130,220,170),true));
            String dev=n.optString("device_label","");
            if(!dev.isEmpty())card.addView(txt(dev,12,Color.rgb(150,170,167),false));
            String err=n.optString("last_error","");
            if(!err.isEmpty())card.addView(txt(err,12,Color.rgb(255,170,80),true));
            body.addView(card);
        }
    }

    void renderCamera(LinearLayout body) {
        activeScreen="camera";
        body.removeAllViews();
        body.addView(txt("Kamera / Handyfoto",20,Color.WHITE,true));
        body.addView(noteView("Handy-Notfallprint. Der normale Eventbetrieb mit SD-Karte/WLAN und automatischer Mehrdrucker-Verteilung läuft über den Mac-Print-Host. Fotos bleiben lokal und gehen nicht in die öffentliche Selfie-Galerie."));
        Button choose=button("Foto von Handy / SD-Karte auswählen");
        body.addView(choose);
        TextView sel=txt(selectedLocalName==null?"Noch kein Foto ausgewählt.":"Ausgewählt: "+selectedLocalName,13,Color.rgb(170,185,182),false);
        body.addView(sel);
        if(selectedLocalPhoto!=null){
            ImageView preview=new ImageView(this);preview.setAdjustViewBounds(true);preview.setScaleType(ImageView.ScaleType.CENTER_INSIDE);
            try(InputStream in=getContentResolver().openInputStream(selectedLocalPhoto)){preview.setImageBitmap(BitmapFactory.decodeStream(in));}catch(Exception ignored){}
            body.addView(preview,new LinearLayout.LayoutParams(-1,dp(300)));
            Button print=button("Foto drucken");
            Button booked=secondaryButton("Als Kamera-Print buchen");
            body.addView(print);body.addView(booked);
            print.setOnClickListener(v->printUri(selectedLocalPhoto,"FTS Kamera · "+selectedLocalName));
            booked.setOnClickListener(v->logCameraPrint());
        }
        choose.setOnClickListener(v->{
            Intent i=new Intent(Intent.ACTION_OPEN_DOCUMENT);
            i.setType("image/*");i.addCategory(Intent.CATEGORY_OPENABLE);
            startActivityForResult(i,9001);
        });
    }

    @Override protected void onActivityResult(int req,int res,Intent data){
        super.onActivityResult(req,res,data);
        if(req==9001&&res==RESULT_OK&&data!=null&&data.getData()!=null){
            selectedLocalPhoto=data.getData();
            try{getContentResolver().takePersistableUriPermission(selectedLocalPhoto,Intent.FLAG_GRANT_READ_URI_PERMISSION);}catch(Exception ignored){}
            selectedLocalName=queryName(selectedLocalPhoto);
            activeScreen="camera";
            View b=findTagged(content,"body");if(b instanceof LinearLayout)renderCamera((LinearLayout)b);
        }
    }

    void printOrderImage(OrderModel o){
        if(o.firstPath==null){toast("Keine Druckdatei.");return;}
        io.execute(()->{
            try{
                Bitmap bm=downloadBitmap(storageURL(o.firstPath));
                runOnUiThread(()->printBitmap(bm,"FTS Selfie · "+safe(o.pickupCode,o.id)));
            }catch(Exception e){runOnUiThread(()->error(e.getMessage()));}
        });
    }

    void confirmPrinted(OrderModel o){
        new AlertDialog.Builder(this).setTitle("Druck bestätigen")
                .setMessage("Wurde der Auftrag wirklich erfolgreich ausgedruckt?")
                .setNegativeButton("Nein",null)
                .setPositiveButton("Ja, gedruckt",(d,w)->rpc("fts_printer_mark_printed_v73",obj(
                        "p_device_token",deviceToken,"p_session_token",sessionToken,"p_order_id",o.id
                ), r->{toast(Boolean.TRUE.equals(r)?"Als gedruckt gespeichert.":"Auftrag konnte nicht bestätigt werden.");refreshSelected();}))
                .show();
    }

    void markPickedUp(OrderModel o){
        rpc("fts_printer_mark_picked_up_archive_v80",obj(
                "p_device_token",deviceToken,"p_session_token",sessionToken,"p_order_id",o.id
        ),r->{toast(Boolean.TRUE.equals(r)?"Abgeholt und archiviert.":"Noch nicht abholbereit.");refreshSelected();});
    }

    void showReceipt(OrderModel o){
        rpc("fts_printer_receipt_v73",obj(
                "p_device_token",deviceToken,"p_session_token",sessionToken,"p_order_id",o.id
        ), result -> {
            if(!(result instanceof JSONObject)){toast("Kein Kundenbeleg vorhanden.");return;}
            JSONObject x=(JSONObject)result;
            int cents=Math.max(0,x.optInt("total_cents",0)-x.optInt("refund_cents",0));
            String text="FTS.LU · FOTO-PRINT\n\n"+
                    "Beleg: "+x.optString("receipt_number","—")+"\n"+
                    "Event: "+x.optString("event_title","—")+"\n"+
                    "Veranstalter: "+x.optString("organizer_name","—")+"\n"+
                    "Eventdatum: "+x.optString("event_date","—")+"\n\n"+
                    "Anzahl Prints: "+x.optInt("quantity_total",0)+"\n"+
                    "Betrag: "+String.format(Locale.GERMANY,"%.2f",cents/100.0)+" "+x.optString("currency","EUR")+"\n"+
                    "Zahlungsart: "+x.optString("payment_method","—")+"\n"+
                    "Status: "+x.optString("payment_status","—")+"\n"+
                    "Abholcode: "+x.optString("pickup_code","—")+
                    (x.optBoolean("is_test",false)?"\n\nTEST · KEIN ECHTER UMSATZ":"");
            LinearLayout wrap=new LinearLayout(this);wrap.setPadding(dp(22),dp(10),dp(22),dp(10));wrap.setOrientation(LinearLayout.VERTICAL);
            TextView tv=txt(text,15,Color.DKGRAY,false);tv.setTypeface(android.graphics.Typeface.MONOSPACE);wrap.addView(tv);
            new AlertDialog.Builder(this).setTitle("Kundenbeleg").setView(wrap)
                    .setNegativeButton("Schließen",null)
                    .setPositiveButton("Drucken",(d,w)->printText(text,"FTS Kundenbeleg"))
                    .show();
        });
    }

    void checkUpdate(){
        rpc("fts_printer_latest_release_v80",obj("p_platform","android"),result->{
            if(result instanceof JSONArray){
                JSONArray a=(JSONArray)result;
                if(a.length()>0){
                    JSONObject rel=a.optJSONObject(0);
                    if(rel!=null && rel.optInt("build_number",0)>BuildConfig.VERSION_CODE){
                        AppUpdater.offer(this,rel);
                    }
                }
            }
        });
    }

    void showStockDialog(){
        LinearLayout w=new LinearLayout(this);w.setOrientation(LinearLayout.VERTICAL);w.setPadding(dp(20),dp(6),dp(20),0);
        if(stock!=null){
            w.addView(txt("Sicher verfügbar: "+stock.optInt("safe_available",0),22,Color.DKGRAY,true));
            w.addView(txt("Selfie gedruckt: "+stock.optInt("selfie_printed",0)+" · Kamera: "+stock.optInt("camera_prints",0)+" · Kamera wartet: "+stock.optInt("camera_waiting",0),13,Color.GRAY,false));
            w.addView(txt("RP-108: 108 Prints = 6 × 18 Blatt + 2 × 54 Farbfilm",12,Color.GRAY,false));
            if(stock.optBoolean("open_stock_unknown",false))w.addView(txt("Geöffneter Bestand unbekannt – wird nicht für neue Zahlungen gerechnet.",12,Color.rgb(170,110,0),true));
        }
        Spinner kind=new Spinner(this);
        ArrayList<String> labels=new ArrayList<>(Arrays.asList("Nachschub hinzufügen","Kamera-/Standprint","Testdruck","Fehldruck","Nachdruck"));
        ArrayList<String> values=new ArrayList<>(Arrays.asList("ADD_STOCK","CAMERA_PRINT","TEST_PRINT","MISPRINT","REPRINT"));
        if("printer_admin".equals(currentRole)){labels.add("Korrektur + / −");values.add("CORRECTION");}
        kind.setAdapter(new ArrayAdapter<>(this,android.R.layout.simple_spinner_dropdown_item,labels));
        EditText qty=input("Menge, z. B. 108",false);qty.setInputType(InputType.TYPE_CLASS_NUMBER|InputType.TYPE_NUMBER_FLAG_SIGNED);qty.setText("108");
        EditText note=input("Notiz optional",false);
        EditText pin=input("Persönlichen Code erneut eingeben",true);pin.setInputType(InputType.TYPE_CLASS_NUMBER|InputType.TYPE_NUMBER_VARIATION_PASSWORD);
        w.addView(kind);w.addView(qty);w.addView(note);w.addView(pin);
        AlertDialog dlg=new AlertDialog.Builder(this).setTitle("Materialbestand").setView(w)
                .setNegativeButton("Schließen",null)
                .setPositiveButton("Buchen",null).create();
        dlg.setOnShowListener(x->dlg.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(v->{
            int q;try{q=Integer.parseInt(qty.getText().toString().trim());}catch(Exception e){toast("Gültige Menge eingeben.");return;}
            String code=pin.getText().toString().trim();if(code.isEmpty()){toast("Persönlichen Code erneut eingeben.");return;}
            String k=values.get(kind.getSelectedItemPosition());
            rpc("fts_printer_adjust_stock_v73",obj(
                    "p_device_token",deviceToken,"p_session_token",sessionToken,"p_code",code,
                    "p_event_token",selectedEventToken,"p_event_day",today(),"p_kind",k,"p_quantity",q,
                    "p_note",note.getText().toString().trim()
            ),r->{toast("Bestand aktualisiert.");dlg.dismiss();refreshSelected();});
        }));
        dlg.show();
    }

    void logCameraPrint(){
        if(selectedLocalPhoto==null)return;
        new AlertDialog.Builder(this).setTitle("Kamera-Print buchen")
                .setMessage("Nur bestätigen, wenn dieses Foto wirklich gedruckt wurde. Der Materialbestand wird um 1 reduziert.")
                .setNegativeButton("Abbrechen",null)
                .setPositiveButton("Ja, gedruckt",(d,w)->rpc("fts_printer_log_camera_print_v73",obj(
                        "p_device_token",deviceToken,"p_session_token",sessionToken,"p_event_token",selectedEventToken,
                        "p_event_day",today(),"p_quantity",1,"p_file_name",selectedLocalName
                ),r->{toast("Kamera-Print gebucht.");refreshSelected();}))
                .show();
    }

    void logoutAndSwitch(){
        onMain=false;handler.removeCallbacksAndMessages(null);
        rpc("fts_printer_logout_v72",obj("p_device_token",deviceToken,"p_session_token",sessionToken),r->{});
        sessionToken="";workUnits.clear();pickupRows.clear();printerNodes.clear();archiveRows.clear();prefs.edit().remove("session_token").apply();loadStaff();
    }

    interface RpcCallback { void done(Object result); }

    void rpc(String name, JSONObject body, RpcCallback cb){
        io.execute(()->{
            HttpURLConnection c=null;
            try{
                URL u=new URL(SUPABASE+"/rest/v1/rpc/"+name);
                c=(HttpURLConnection)u.openConnection();
                c.setRequestMethod("POST");c.setConnectTimeout(12000);c.setReadTimeout(20000);c.setDoOutput(true);
                c.setRequestProperty("apikey",KEY);c.setRequestProperty("Authorization","Bearer "+KEY);c.setRequestProperty("Content-Type","application/json");
                try(OutputStream os=c.getOutputStream()){os.write(body.toString().getBytes(StandardCharsets.UTF_8));}
                int code=c.getResponseCode();
                InputStream in=code>=200&&code<300?c.getInputStream():c.getErrorStream();
                String text=readAll(in);
                if(code<200||code>=300){
                    String msg=text;
                    try{JSONObject er=new JSONObject(text);msg=er.optString("message",er.optString("hint",text));}catch(Exception ignored){}
                    final String m=msg;runOnUiThread(()->error(m));return;
                }
                Object result=parseJson(text);
                runOnUiThread(()->cb.done(result));
            }catch(Exception e){runOnUiThread(()->error(e.getMessage()));}
            finally{if(c!=null)c.disconnect();}
        });
    }

    Object parseJson(String t)throws Exception{
        String s=t==null?"":t.trim();
        if(s.startsWith("["))return new JSONArray(s);
        if(s.startsWith("{"))return new JSONObject(s);
        if("true".equals(s))return Boolean.TRUE;
        if("false".equals(s))return Boolean.FALSE;
        if("null".equals(s)||s.isEmpty())return null;
        if(s.startsWith("\""))return new JSONArray("["+s+"]").getString(0);
        return s;
    }

    void loadImage(String path,ImageView target){
        io.execute(()->{
            try{Bitmap b=downloadBitmap(storageURL(path));runOnUiThread(()->target.setImageBitmap(b));}catch(Exception ignored){}
        });
    }

    String storageURL(String path)throws Exception{
        String[] parts=path.split("/");StringBuilder sb=new StringBuilder();
        for(String p:parts){if(sb.length()>0)sb.append("/");sb.append(URLEncoder.encode(p,"UTF-8").replace("+","%20"));}
        return SUPABASE+"/storage/v1/object/public/"+BUCKET+"/"+sb;
    }

    Bitmap downloadBitmap(String url)throws Exception{
        HttpURLConnection c=(HttpURLConnection)new URL(url).openConnection();c.setConnectTimeout(12000);c.setReadTimeout(20000);
        try(InputStream in=c.getInputStream()){return BitmapFactory.decodeStream(in);}finally{c.disconnect();}
    }

    void printUri(Uri uri,String title){
        try(InputStream in=getContentResolver().openInputStream(uri)){
            Bitmap b=BitmapFactory.decodeStream(in);printBitmap(b,title);
        }catch(Exception e){error(e.getMessage());}
    }

    void printBitmap(Bitmap bitmap,String title){
        if(bitmap==null){toast("Foto konnte nicht geöffnet werden.");return;}
        PrintManager pm=(PrintManager)getSystemService(PRINT_SERVICE);
        pm.print(title,new BitmapAdapter(this,bitmap,title),new PrintAttributes.Builder()
                .setMediaSize(PrintAttributes.MediaSize.NA_INDEX_4X6)
                .setColorMode(PrintAttributes.COLOR_MODE_COLOR).build());
    }

    void printText(String text,String title){
        PrintManager pm=(PrintManager)getSystemService(PRINT_SERVICE);
        pm.print(title,new TextAdapter(this,text,title),null);
    }

    static class BitmapAdapter extends PrintDocumentAdapter {
        final Context ctx; final Bitmap bitmap; final String title; PrintAttributes attrs;
        BitmapAdapter(Context c,Bitmap b,String t){ctx=c;bitmap=b;title=t;}
        public void onLayout(PrintAttributes oldA,PrintAttributes newA,CancellationSignal cs,LayoutResultCallback cb,Bundle ex){
            attrs=newA;cb.onLayoutFinished(new PrintDocumentInfo.Builder(title+".pdf").setContentType(PrintDocumentInfo.CONTENT_TYPE_PHOTO).setPageCount(1).build(),true);
        }
        public void onWrite(PageRange[] ranges,ParcelFileDescriptor dest,CancellationSignal cs,WriteResultCallback cb){
            PrintedPdfDocument pdf=new PrintedPdfDocument(ctx,attrs);
            PdfDocument.Page page=pdf.startPage(0);
            RectF r=new RectF(page.getInfo().getContentRect());
            float scale=Math.min(r.width()/bitmap.getWidth(),r.height()/bitmap.getHeight());
            float w=bitmap.getWidth()*scale,h=bitmap.getHeight()*scale;
            RectF out=new RectF(r.left+(r.width()-w)/2,r.top+(r.height()-h)/2,r.left+(r.width()+w)/2,r.top+(r.height()+h)/2);
            page.getCanvas().drawColor(Color.WHITE);page.getCanvas().drawBitmap(bitmap,null,out,new Paint(Paint.FILTER_BITMAP_FLAG));
            pdf.finishPage(page);
            try{pdf.writeTo(new FileOutputStream(dest.getFileDescriptor()));cb.onWriteFinished(new PageRange[]{PageRange.ALL_PAGES});}
            catch(Exception e){cb.onWriteFailed(e.getMessage());}
            finally{pdf.close();}
        }
    }

    static class TextAdapter extends PrintDocumentAdapter {
        final Context ctx; final String text,title; PrintAttributes attrs;
        TextAdapter(Context c,String s,String t){ctx=c;text=s;title=t;}
        public void onLayout(PrintAttributes o,PrintAttributes n,CancellationSignal cs,LayoutResultCallback cb,Bundle ex){
            attrs=n;cb.onLayoutFinished(new PrintDocumentInfo.Builder(title+".pdf").setContentType(PrintDocumentInfo.CONTENT_TYPE_DOCUMENT).setPageCount(1).build(),true);
        }
        public void onWrite(PageRange[] rs,ParcelFileDescriptor dest,CancellationSignal cs,WriteResultCallback cb){
            PrintedPdfDocument pdf=new PrintedPdfDocument(ctx,attrs);PdfDocument.Page page=pdf.startPage(0);
            Paint p=new Paint();p.setColor(Color.BLACK);p.setTextSize(12*ctx.getResources().getDisplayMetrics().scaledDensity);p.setTypeface(Typeface.MONOSPACE);
            float x=page.getInfo().getContentRect().left+18,y=page.getInfo().getContentRect().top+30;
            for(String line:text.split("\n",-1)){page.getCanvas().drawText(line,x,y,p);y+=22;}
            pdf.finishPage(page);
            try{pdf.writeTo(new FileOutputStream(dest.getFileDescriptor()));cb.onWriteFinished(new PageRange[]{PageRange.ALL_PAGES});}
            catch(Exception e){cb.onWriteFailed(e.getMessage());}finally{pdf.close();}
        }
    }

    static class Staff {String id,name,role;Staff(String i,String n,String r){id=i;name=n;role=r;}}
    static class EventModel {String token,code,title,location,date;boolean printActive,localCamera;EventModel(String t,String c,String ti,String l,String d,boolean p,boolean lc){token=t;code=c;title=ti;location=l;date=d;printActive=p;localCamera=lc;}}
    static class OrderModel {
        String id,paymentStatus,printStatus,pickupCode,pickupStatus,receiptNumber,firstPath;int qty;boolean ready,test;
        OrderModel(JSONObject o){
            id=o.optString("order_id");paymentStatus=o.optString("payment_status");printStatus=o.optString("print_status");
            pickupCode=o.optString("pickup_code");pickupStatus=o.optString("pickup_status");receiptNumber=o.optString("receipt_number");
            qty=o.optInt("quantity_total",0);test=o.optBoolean("is_test",false);
            ready=(paymentStatus.equals("COMPLETED")||paymentStatus.equals("COVERED")||paymentStatus.equals("FREE"))&&printStatus.equals("READY");
            JSONArray items=o.optJSONArray("items");if(items!=null&&items.length()>0){JSONObject i=items.optJSONObject(0);if(i!=null)firstPath=i.optString("designed_path",null);}
        }
    }

    JSONObject obj(Object... kv){
        JSONObject o=new JSONObject();
        try{for(int i=0;i+1<kv.length;i+=2)o.put(String.valueOf(kv[i]),kv[i+1]);}catch(Exception ignored){}
        return o;
    }

    void clear(){content.removeAllViews();}
    void addHeading(String s){content.addView(txt(s,24,Color.WHITE,true));}
    void addNote(String s){content.addView(noteView(s));}
    TextView noteView(String s){TextView t=txt(s,13,Color.rgb(150,170,167),false);t.setPadding(0,dp(8),0,dp(12));return t;}
    TextView txt(String s,int sp,int color,boolean bold){TextView t=new TextView(this);t.setText(s);t.setTextSize(sp);t.setTextColor(color);if(bold)t.setTypeface(Typeface.DEFAULT,Typeface.BOLD);return t;}
    EditText input(String hint,boolean secure){EditText e=new EditText(this);e.setHint(hint);e.setTextColor(Color.WHITE);e.setHintTextColor(Color.rgb(110,135,132));e.setSingleLine(true);e.setPadding(dp(12),dp(10),dp(12),dp(10));e.setBackground(round(Color.rgb(10,36,38),Color.rgb(50,72,73),12));if(secure)e.setTransformationMethod(PasswordTransformationMethod.getInstance());e.setLayoutParams(margins(-1,dp(52),0,dp(7)));return e;}
    Button button(String s){Button b=new Button(this);b.setText(s);b.setTextColor(Color.rgb(5,25,26));b.setTextSize(14);b.setTypeface(Typeface.DEFAULT,Typeface.BOLD);b.setBackground(round(Color.rgb(216,181,109),Color.TRANSPARENT,12));b.setPadding(dp(12),0,dp(12),0);b.setLayoutParams(margins(-2,dp(48),dp(6),dp(6)));return b;}
    Button secondaryButton(String s){Button b=button(s);b.setTextColor(Color.WHITE);b.setBackground(round(Color.rgb(20,66,68),Color.rgb(50,90,90),12));return b;}
    LinearLayout row(){LinearLayout l=new LinearLayout(this);l.setOrientation(LinearLayout.HORIZONTAL);l.setGravity(Gravity.CENTER_VERTICAL);l.setPadding(0,dp(6),0,dp(6));return l;}
    LinearLayout card(){LinearLayout l=new LinearLayout(this);l.setOrientation(LinearLayout.VERTICAL);l.setPadding(dp(14),dp(14),dp(14),dp(14));l.setBackground(round(Color.rgb(10,36,38),Color.rgb(45,62,63),16));l.setLayoutParams(margins(-1,-2,0,dp(10)));return l;}
    GradientDrawable round(int fill,int stroke,float radius){GradientDrawable g=new GradientDrawable();g.setColor(fill);g.setCornerRadius(dp((int)radius));if(stroke!=Color.TRANSPARENT)g.setStroke(dp(1),stroke);return g;}
    LinearLayout.LayoutParams margins(int w,int h,int l,int b){LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(w,h);p.setMargins(l,dp(6),0,b);return p;}
    Space space(int d){Space s=new Space(this);s.setLayoutParams(new LinearLayout.LayoutParams(1,dp(d)));return s;}
    int dp(int n){return (int)(n*getResources().getDisplayMetrics().density+0.5f);}
    String safe(String s,String d){return s==null||s.isEmpty()||"null".equals(s)?d:s;}
    String readAll(InputStream in)throws Exception{if(in==null)return"";ByteArrayOutputStream b=new ByteArrayOutputStream();byte[] buf=new byte[8192];int n;while((n=in.read(buf))>0)b.write(buf,0,n);return b.toString("UTF-8");}
    String today(){return new SimpleDateFormat("yyyy-MM-dd",Locale.GERMANY).format(new Date());}
    String queryName(Uri u){String name="Foto";Cursor c=null;try{c=getContentResolver().query(u,null,null,null,null);if(c!=null&&c.moveToFirst()){int i=c.getColumnIndex(OpenableColumns.DISPLAY_NAME);if(i>=0)name=c.getString(i);}}finally{if(c!=null)c.close();}return name;}
    View findTagged(ViewGroup g,String tag){for(int i=0;i<g.getChildCount();i++){View v=g.getChildAt(i);if(tag.equals(v.getTag()))return v;if(v instanceof ViewGroup){View x=findTagged((ViewGroup)v,tag);if(x!=null)return x;}}return null;}
    void status(String s){statusText.setText(s);}
    void toast(String s){Toast.makeText(this,s,Toast.LENGTH_LONG).show();}
    void error(String s){
        String msg=s==null?"Unbekannter Fehler":s;
        if(recoveringAuth)return;
        if(msg.toLowerCase(Locale.ROOT).contains("printer-sitzung ist nicht gültig")){
            recoveringAuth=true;
            onMain=false;
            handler.removeCallbacksAndMessages(null);
            sessionToken="";
            currentUser="";
            currentRole="";
            orders.clear();
            stock=null;
            prefs.edit().remove("session_token").apply();
            toast("Printer-Sitzung abgelaufen. Bitte Mitarbeiter neu anmelden.");
            recoveringAuth=false;
            loadStaff();
            return;
        }
        if(msg.toLowerCase(Locale.ROOT).contains("printer-gerät nicht freigeschaltet")){
            recoveringAuth=true;
            onMain=false;
            handler.removeCallbacksAndMessages(null);
            sessionToken="";
            deviceToken="";
            currentUser="";
            currentRole="";
            events.clear();
            orders.clear();
            stock=null;
            prefs.edit().remove("session_token").remove("device_token").apply();
            toast("Gerätefreigabe muss erneuert werden.");
            recoveringAuth=false;
            loadDeviceAdmins();
            return;
        }
        new AlertDialog.Builder(this).setTitle("FTS Printer").setMessage(msg).setPositiveButton("OK",null).show();
    }
}
