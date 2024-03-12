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
    <a href="https://apps.apple.com/us/app/fppmon/id6445864655"><img alt='Get it in the App Store' src="images/plugin/fpp-FPPMon/images/AppleAppStore.png" width="150"></a>
    <a href="https://play.google.com/store/apps/details?id=com.kulplights.fppmon"><img alt='Get it on Google Play' src="images/plugin/fpp-FPPMon/images/google-play-badge.png" width="150"></a>
</div>
</div>
<div class="container-fluid" id="connectedDiv">
FPP Remote Monitoring Connected<br>
<div class=" row">
<div class="backdrop col-auto" id="userInfoDiv"></div>
<div class="col-1"></div>
<div class="col-1">
    <a href="https://apps.apple.com/us/app/fppmon/id6445864655"><img alt='Get it in the App Store' src="images/plugin/fpp-FPPMon/images/AppleAppStore.png" width="150"></a><br>
    <a href="https://play.google.com/store/apps/details?id=com.kulplights.fppmon"><img alt='Get it on Google Play' src="images/plugin/fpp-FPPMon/images/google-play-badge.png" width="150"></a><br>
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
    foreach ($arr["systems"] as $i) {
        // FPP Systems are 0x01 to 0x80
        if ($i["typeId"] >= 1 && $i["typeId"] < 0xC0) {
            if ($i["typeId"] < 0x80) {
                echo "<div class='row'>";
            } else if ($i["typeId"] < 0xC0) {
                echo "<div class='row otherControllerType'>";
            }
            PrintSettingCheckbox($i["hostname"] . "-" .  $i["address"], "FPPMon_" . $i["address"], 1, 0, 1, 0, "fpp-FPPMon", "", 0);
            echo "&nbsp;" . $i["hostname"] . "/" .  $i["address"];
            unset($origSystemSettings["FPPMon_" . $i["address"]]);
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
</div>
