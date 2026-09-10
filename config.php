<?php
$output = array();
exec($settings['fppDir'] . "/scripts/get_uuid", $output);
$uuid = $output[0];

// Both panels show the store badges. Held in one place so they cannot drift
// apart again: the two copies had already grown different separators, and sat
// in different places on the page because only one of them was inside a row.
$storeBadges = <<<'HTML'
    <a href="https://apps.apple.com/us/app/fppmon/id6445864655"><img alt='Get it in the App Store' src="images/plugin/fpp-FPPMon/images/AppleAppStore.png" height="48"></a><br>
    <a href="https://play.google.com/store/apps/details?id=com.kulplights.fppmon"><img alt='Get it on Google Play' src="images/plugin/fpp-FPPMon/images/google-play-badge.png" height="48"></a><br>
    <a href="https://apps.microsoft.com/detail/9pj02xstxjhr"><img alt='Download from the Microsoft Store' src="images/plugin/fpp-FPPMon/images/MicrosoftStore.png" height="48"></a><br>
    <a href="https://kulplights.com/FPPMon/downloads/latest/"><img alt='Download for Linux' src="images/plugin/fpp-FPPMon/images/LinuxDownload.png" height="48"></a><br>
HTML;
?>
<script>
function ShowConnecting() {
    $("#loginDiv").hide();
    $("#connectedDiv").hide();
    $("#notRunningDiv").hide();
    $("#connectingDiv").show();
}
// Waits out a login attempt. Only three states are an answer; everything else
// -- Connecting, Could not connect, Unknown -- means the attempt has not
// resolved yet, so keep waiting rather than drawing the login form back over a
// login that is still working. Measured against real hardware, reaching
// Connected took 8s when the token came back first time and ~26s when the
// token fetch retried once, so the patience here is in that order rather than
// the couple of seconds it used to be. When it does run out, render whatever
// is actually true rather than assuming failure.
function AwaitLogin(triesLeft) {
    ShowConnecting();
    $.ajax({
        url: "api/plugin-apis/FPPMon",
        type: "GET",
        dataType: 'json',
        cache: false,
        success: function (data) {
            var status = data['status'];
            if (status == "Connected" || status == "Invalid Credentials" ||
                status == "No Credentials" || triesLeft <= 0) {
                CheckStatus();
                return;
            }
            setTimeout(function () { AwaitLogin(triesLeft - 1); }, 1000);
        },
        error: function () { CheckStatus(); }
    });
}
// Reads the plugin's state and redraws from it. Connecting is not a settled
// answer, so keep asking until it becomes one -- the page used to sample this
// once on load, which meant any state that settled a moment later was never
// shown and the user had to refresh by hand to see they were logged in.
function CheckStatus() {
    $.ajax({
        url: "api/plugin-apis/FPPMon",
        type: "GET",
        dataType: 'json',
        cache: false,
        success: function (data) {
            if (data['pluginVersion']) {
                $("#pluginVersionDiv").text("Plugin build: " + data['pluginVersion']);
            }
            if (data['status'] == "Connecting") {
                // An older .so never reports this; it is only reachable from a
                // build that distinguishes "not yet" from "rejected".
                ShowConnecting();
                setTimeout(CheckStatus, 1000);
                return;
            }
            $("#connectingDiv").hide();
            if (data['status'] == "Connected") {
                var html = "<div><b>" + data["name"] + "</b><br>";
                html += data["email"] + "<br><br>";
                html += "Subscription:<br>";
                html += data["maxFPP"] + " FPP Instances<br>";
                html += data["maxKulp"] + " KulpLights Controllers<br>";
                html += data["maxOther"] + " Non FPP Controllers<br>";
                html += "<div><input type='button' class='buttons buttons-rounded' value='Logout' onclick='LogoutFromKulpLights()''></div></div>";
                $("#userInfoDiv").html(html);
                $("#userInfoDiv").show();
                $("#loginDiv").hide();
                $("#connectedDiv").show();
                $("#notRunningDiv").hide();

                if (data["maxOther"] == 0) {
                    $(".otherControllerType").hide();
                }
            } else {
                $("#loginDiv").show();
                $("#userInfoDiv").hide();
                $("#connectedDiv").hide();
                $("#notRunningDiv").hide();
            }
        },
        error: function(data) {
            $("#connectedDiv").hide();
            $("#userInfoDiv").hide();
            $("#loginDiv").hide();
            $("#connectingDiv").hide();
            $("#notRunningDiv").show();
        }
    });
}

// Builds the credentials body from a login response. The plugin requires all
// three keys and rejects a body missing any of them -- which is deliberate,
// since this POST replaces the stored credentials outright and an incomplete
// one used to be enough to destroy a working login. So coerce each value:
// JSON.stringify drops a key whose value is undefined, so reading a field that
// is not there does not send an empty string, it sends no key at all, and the
// POST is rejected with nothing to show for it.
function SaveCredentials(data) {
    var creds = new Object();
    creds['username'] = data['data']['nicename'] || "";
    creds['token'] = data['data']['token'] || "";
    creds['refresh_token'] = data['refresh_token'] || "";

    $.ajax({
        url: "api/plugin-apis/FPPMon/credentials",
        type: "POST",
        async: false,
        contentType: 'application/json',
        data:  JSON.stringify(creds, null, 2),
        success: function (data) {
            // A rejected POST is answered with 200 and a status of "error", so
            // jQuery calls this handler either way. Reloading on that redraws
            // the page in whatever state it was already in, which is what made
            // a failed logout look like nothing happening at all.
            var reply = data;
            if (typeof reply === "string") {
                try { reply = JSON.parse(reply); } catch (e) { reply = {}; }
            }
            if (reply && reply['status'] == "error") {
                $.jGrowl("FPPMon: the plugin rejected that request.");
                return;
            }
            // The plugin applies the new credentials as soon as this POST
            // lands (it re-runs its connection to the monitoring service), so
            // no fppd restart is needed here -- and restarting fppd from a
            // settings page would kill a running show.
            if (creds['username'] == "") {
                location.reload();  // logout: redraw the server-rendered page
                return;
            }
            // Logging in redraws from the polled state rather than reloading.
            // A reload was a single sample taken at whatever instant it landed:
            // too early and it caught the connect still in flight and drew the
            // login form back over a login that was working.
            AwaitLogin(90);
        },
        error: function () {
            location.reload();
        }
    });

}
// Logging out is the same POST with all three values empty. The shape has to
// match what SaveCredentials reads out of a real login response: nicename and
// token nested under data, refresh_token at the top level. It used to put
// refresh_token under data as well, so the key SaveCredentials looked for was
// not there and the logout went out a key short and was ignored.
function LogoutFromKulpLights() {
    var data = new Object();
    data['data'] = new Object();
    data['data']['nicename'] = "";
    data['data']['token'] = "";
    data['refresh_token'] = "";

    SaveCredentials(data);
}
function LoginToKulpLights() {
    var un = $("#klusername").val();
    var pwd = $("#klpassword").val();
    var deviceid = "<?= $uuid?>";

    //var data = "username=" + encodeURIComponent(un) + "&password=" + encodeURIComponent(pwd) + "&device=" + encodeURIComponent(deviceid);
    var data = new Object();
    data['username'] = un;
    data['password'] = pwd;
    data['device'] = deviceid;
    
    $.ajax({
        url: "https://kulplights.com/wp-json/jwt-auth/v1/token",
        type: "POST",
        contentType: 'application/x-www-form-urlencoded',
        data: data,
        dataType: 'json',
        success: function (data) {
            SaveCredentials(data);
        },
        error: function (data) {
            $.jGrowl(data['message']);
        }
    });
}

$(document).ready(function() {CheckStatus();});
</script>

<div id="global" class="settings">
<h2>FPP Remote Monitoring Plugin</h2>
<div class="container-fluid settingsTable settingsGroupTable" id="loginDiv" style="display:none">
<div class="row"><div class="col-5">Login with your <a href="https://kulplights.com">KulpLights</a> account credentials</div></div>
<div class="row">
<!-- Fixed width rather than col-auto so the badges beside it line up with the
     ones on the connected panel, whose card is a different width. col-12 below
     md so the badges drop underneath on a narrow screen instead of squeezing. -->
<div class="col-12 col-md-4">
<!-- col-auto, not col-1: these rows sit inside a column now, so a twelfth is a
     twelfth of that column rather than of the page, which is narrower than the
     word "Username:". Sizing the label to its own text does not care how wide
     the container is. The button lines up with the fields by reserving that
     same width with a copy of the widest label rather than a fixed column, so
     it stays lined up whatever the text or font size. -->
<div class="row"><div class="printSettingLabelCol description col-auto">Username:</div><div class="col-auto"><input type='text' id='klusername'></div></div>
<div class="row"><div class="printSettingLabelCol description col-auto">Password:</div><div class="col-auto"><input type='password' id='klpassword'></div></div>
<div class="row"><div class="printSettingLabelCol description col-auto" style="visibility:hidden" aria-hidden="true">Username:</div><div class="col-auto"><input type='button' class='buttons buttons-rounded' value="Login" onclick="LoginToKulpLights()"></div></div>
</div>
<div class="col-12 col-md-auto">
<?= $storeBadges ?>
</div>
</div>
</div>
<div class="container-fluid" id="connectedDiv" style="display:none">
FPP Remote Monitoring Connected<br>
<div class=" row">
<div class="backdrop col-12 col-md-4" id="userInfoDiv"></div>
<div class="col-12 col-md-auto">
<?= $storeBadges ?>
</div>
</div>
</div>
<div class="container-fluid settingsTable settingsGroupTable" id="connectingDiv" style="display:none">
Connecting to FPP Remote Monitoring...
</div>
<div class="container-fluid settingsTable settingsGroupTable" id="notRunningDiv" style="display:none">
FPP Remote Monitoring Plugin Not Running.  Restart FPPD to enable.
</div>
<br>
<div class="container-fluid settingsTable settingsGroupTable">    
    <div class="row">Select FPP Instances and Controllers to Monitor:</div>
<?
// Via the web server's documented proxy, not fppd's internal port directly.
$arr = json_decode(file_get_contents("http://localhost/api/fppd/multiSyncSystems"), true);
$origSystemSettings = $pluginSettings;

// Ask the running plugin whether it picks a changed selection up on its own.
// It does from the build that advertises liveSystemSelection; an older .so --
// or none loaded at all -- answers without the flag, and those still need an
// fppd restart, so keep asking for one in that case. Short timeout: this is on
// the page's critical path, and localhost either answers at once or is down.
$restartOnChange = 1;
$ctx = stream_context_create(array('http' => array('timeout' => 2, 'ignore_errors' => true)));
$pluginStatus = @file_get_contents("http://localhost/api/plugin-apis/FPPMon", false, $ctx);
if ($pluginStatus !== false) {
    $ps = json_decode($pluginStatus, true);
    if (is_array($ps) && !empty($ps["liveSystemSelection"])) {
        $restartOnChange = 0;
    }
}
if (array_key_exists("systems", $arr)) {
    // MultiSync advertises every interface address, so one box shows up once
    // per interface (two LANs + loopback + IPv6 can be four rows). Collapse
    // rows sharing a uuid into one entry. Preferences within a group: an
    // address the user already selected always renders (an existing selection
    // must never turn into a hidden checkbox plus a second unchecked row),
    // otherwise IPv4 beats IPv6 beats loopback, ties broken by discovery
    // order. Rows without a usable uuid (hardware controllers, old FPP) are
    // not grouped at all -- keying those on hostname could wrongly merge two
    // identically-named controllers.
    $groups = array();
    $order = array();
    foreach ($arr["systems"] as $i) {
        // Keep this in step with mapType() in the plugin binary -- a row the
        // page offers that the plugin then can't identify is a checkbox that
        // does nothing. FPP systems are 0x01-0x7F; 0x80-0xBF are Falcon and
        // Genius/Experience hardware; 0xC4 is Baldrick and 0xFB is WLED. Note
        // 0x00 is kSysTypeUnknown (an address MultiSync probed but could not
        // identify), not "an FPP", so the range deliberately starts at 1. The
        // rest of 0xC0+ -- xSchedule, ESPixelStick, HinksPix, SanDevices,
        // AlphaPix -- is gear the plugin can't monitor.
        if (($i["typeId"] >= 1 && $i["typeId"] < 0xC0) || $i["typeId"] == 0xC4 || $i["typeId"] == 0xFB) {
            $uuid = isset($i["uuid"]) ? $i["uuid"] : "";
            $key = ($uuid != "" && $uuid != "Unknown") ? "u:" . $uuid : "a:" . $i["address"];
            if (!isset($groups[$key])) {
                $groups[$key] = array();
                $order[] = $key;
            }
            $groups[$key][] = $i;
        }
    }
    foreach ($order as $key) {
        $bestAddr = "";
        $bestScore = 99;
        foreach ($groups[$key] as $i) {
            $addr = $i["address"];
            // Every address of the group counts as "seen" so none of them
            // lands in the (not found) leftovers below.
            unset($origSystemSettings["FPPMon_" . $addr]);
            $selected = isset($pluginSettings["FPPMon_" . $addr]) && $pluginSettings["FPPMon_" . $addr] == "1";
            if ($selected) {
                $score = 0;
            } else if ($addr == "127.0.0.1" || $addr == "::1") {
                $score = 3;
            } else if (strpos($addr, ':') !== false) {
                $score = 2;
            } else {
                $score = 1;
            }
            if ($score < $bestScore) {
                $bestScore = $score;
                $bestAddr = $addr;
            }
        }
        foreach ($groups[$key] as $i) {
            $addr = $i["address"];
            $selected = isset($pluginSettings["FPPMon_" . $addr]) && $pluginSettings["FPPMon_" . $addr] == "1";
            // Render the preferred row, plus any *other* rows the user has
            // selected (both checked, so a redundant selection stays visible
            // and can be cleared); hide only unselected duplicates.
            if ($addr != $bestAddr && !$selected) {
                continue;
            }
            if ($i["typeId"] < 0x80) {
                echo "<div class='row'>";
            } else {
                echo "<div class='row otherControllerType'>";
            }
            // Hardware controllers rarely advertise a name of their own -- a
            // Genius or a Falcon that hasn't been named reports its IP as the
            // hostname, so the row rendered as "192.168.1.243/192.168.1.243"
            // and gave no clue what the device even was. Name it from what
            // MultiSync discovered instead.
            //
            // "model" first, "type" only as a backstop: type is the typeId's
            // label, and every 2.x Genius shares one id (0xAF), so it can say
            // no more than "Genius Controller" for a whole product line. The
            // model is the controller's own string -- "Genius PRO: 16 Port",
            // "Baldrick 8 Port v1" -- which is what tells two rows apart.
            $label = $i["hostname"];
            if ($label == "" || $label == $addr) {
                foreach (array("model", "type") as $f) {
                    if (isset($i[$f]) && $i[$f] != "") {
                        $label = $i[$f];
                        break;
                    }
                }
            }
            PrintSettingCheckbox($label . "-" .  $addr, "FPPMon_" . $addr, $restartOnChange, 0, 1, 0, "fpp-FPPMon", "", 0);
            echo "&nbsp;" . $label . "/" .  $addr;
            echo "</div>";
        }
    }
    foreach ($origSystemSettings as $key => $i) {
        if ($i == "1") {
            echo "<div class='row'>";
            $ip = substr($key, 7);
            PrintSettingCheckbox($ip, $key, $restartOnChange, 0, 1, 0, "fpp-FPPMon", "", 0);
            echo "&nbsp;" . $ip . " (not found)";
            echo "</div>";
        }
    }
}
?>
</div>
<div>
    Please log any bugs/issues/suggestions at <a href="https://github.com/KulpLights/fpp-FPPMon/issues">https://github.com/KulpLights/fpp-FPPMon/issues</a>
</div>
<div id="pluginVersionDiv" class="text-muted"></div>
</div>
