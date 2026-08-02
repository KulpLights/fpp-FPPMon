<?php
$output = array();
exec($settings['fppDir'] . "/scripts/get_uuid", $output);
$uuid = $output[0];
?>
<script>
function CheckStatus() {
    $.ajax({
        url: "api/plugin-apis/FPPMon",
        type: "GET",
        dataType: 'json',
        async: false,
        success: function (data) {
            if (data['pluginVersion']) {
                $("#pluginVersionDiv").text("Plugin build: " + data['pluginVersion']);
            }
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
            $("#notRunningDiv").show();
        }
    });
}

function SaveCredentials(data) {
    var creds = new Object();
    creds['username'] = data['data']['nicename'];
    creds['token'] = data['data']['token'];
    creds['refresh_token'] = data['refresh_token'];

    $.ajax({
        url: "api/plugin-apis/FPPMon/credentials",
        type: "POST",
        async: false,
        contentType: 'application/json',
        data:  JSON.stringify(creds, null, 2),
        success: function (data) {
            SetRestartFlag(2);
            RestartFPPD();
            CheckStatus();
            location.reload();
        },
        error: function () {
            location.reload();
        }
    });

}
function LogoutFromKulpLights() {
    var data = new Object();
    data['data'] = new Object();
    data['data']['nicename'] = "";
    data['data']['token'] = "";
    data['data']['refresh_token'] = "";

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
<div class="container-fluid settingsTable settingsGroupTable" id="loginDiv">
<div class="row"><div class="col-5">Login with your <a href="https://kulplights.com">KulpLights</a> account credentials</div></div>
<div class="row"><div class="printSettingLabelCol description col-1">Username:</div><div class="col-1"><input type='text' id='klusername'></div></div>
<div class="row"><div class="printSettingLabelCol description col-1">Password:</div><div class="col-1"><input type='password' id='klpassword'></div></div>
<div class="row"><div class="col-1"></div><div class="col-1"><input type='button' class='buttons buttons-rounded' value="Login" onclick="LoginToKulpLights()"></div></div>
<div class="col-1">
    <a href="https://apps.apple.com/us/app/fppmon/id6445864655"><img alt='Get it in the App Store' src="images/plugin/fpp-FPPMon/images/AppleAppStore.png" height="48"></a>
    <a href="https://play.google.com/store/apps/details?id=com.kulplights.fppmon"><img alt='Get it on Google Play' src="images/plugin/fpp-FPPMon/images/google-play-badge.png" height="48"></a>
    <a href="https://apps.microsoft.com/detail/9pj02xstxjhr"><img alt='Download from the Microsoft Store' src="images/plugin/fpp-FPPMon/images/MicrosoftStore.png" height="48"></a>
    <a href="https://kulplights.com/FPPMon/downloads/latest/"><img alt='Download for Linux' src="images/plugin/fpp-FPPMon/images/LinuxDownload.png" height="48"></a>
</div>
</div>
<div class="container-fluid" id="connectedDiv">
FPP Remote Monitoring Connected<br>
<div class=" row">
<div class="backdrop col-auto" id="userInfoDiv"></div>
<div class="col-1"></div>
<div class="col-1">
    <a href="https://apps.apple.com/us/app/fppmon/id6445864655"><img alt='Get it in the App Store' src="images/plugin/fpp-FPPMon/images/AppleAppStore.png" height="48"></a><br>
    <a href="https://play.google.com/store/apps/details?id=com.kulplights.fppmon"><img alt='Get it on Google Play' src="images/plugin/fpp-FPPMon/images/google-play-badge.png" height="48"></a><br>
    <a href="https://apps.microsoft.com/detail/9pj02xstxjhr"><img alt='Download from the Microsoft Store' src="images/plugin/fpp-FPPMon/images/MicrosoftStore.png" height="48"></a><br>
    <a href="https://kulplights.com/FPPMon/downloads/latest/"><img alt='Download for Linux' src="images/plugin/fpp-FPPMon/images/LinuxDownload.png" height="48"></a><br>
</div>
</div>
</div>
<div class="container-fluid settingsTable settingsGroupTable" id="notRunningDiv">
FPP Remote Monitoring Plugin Not Running.  Restart FPPD to enable.
</div>
<br>
<div class="container-fluid settingsTable settingsGroupTable">    
    <div class="row">Select FPP Instances and Controllers to Monitor:</div>
<?
$arr = json_decode(file_get_contents("http://localhost:32322/fppd/multiSyncSystems"), true);
$origSystemSettings = $pluginSettings;
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
        // FPP Systems are 0x01 to 0x80; 0x80-0xBF are Falcon/Genius hardware
        // controllers; 0xFB is WLED. The rest of the 0xC0+ range is gear the
        // plugin can't monitor.
        if (($i["typeId"] >= 1 && $i["typeId"] < 0xC0) || $i["typeId"] == 0xFB) {
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
            PrintSettingCheckbox($i["hostname"] . "-" .  $addr, "FPPMon_" . $addr, 1, 0, 1, 0, "fpp-FPPMon", "", 0);
            echo "&nbsp;" . $i["hostname"] . "/" .  $addr;
            echo "</div>";
        }
    }
    foreach ($origSystemSettings as $key => $i) {
        if ($i == "1") {
            echo "<div class='row'>";
            $ip = substr($key, 7);
            PrintSettingCheckbox($ip, $key, 1, 0, 1, 0, "fpp-FPPMon", "", 0);
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
