B=${1:-http://localhost:5025}; E="t$RANDOM@x.com"; J='Content-Type: application/json'
for i in $(seq 1 30); do curl -s -o /dev/null $B/swagger/v1/swagger.json && break; sleep 1; done
py() { python -c "import sys,json;print(json.load(sys.stdin)$1)"; }
A=$(curl -s -X POST $B/api/auth/register -H "$J" -d "{\"email\":\"$E\",\"password\":\"password123\"}" | py "['accessToken']")
CODE=$(curl -s -X POST $B/api/pairing/code -H "$J" -H "Authorization: Bearer $A" -d '{"deviceName":"Con"}' | py "['code']")
CL=$(curl -s -X POST $B/api/pairing/claim -H "$J" -d "{\"code\":\"$CODE\"}")
DT=$(echo $CL | py "['deviceToken']"); DID=$(echo $CL | py "['deviceId']")
NOW=$(date -u +%FT%TZ)
echo "device $DID"
curl -s -o /dev/null -w "loc post %{http_code}\n" -X POST $B/api/devices/me/locations -H "$J" -H "Authorization: Bearer $DT" -d "{\"points\":[{\"lat\":10.77,\"lng\":106.7,\"accuracy\":12,\"time\":\"$NOW\"}]}"
curl -s -w "\nloc get %{http_code}\n" $B/api/devices/$DID/location -H "Authorization: Bearer $A"
curl -s -w "\nput gf %{http_code}\n" -X PUT $B/api/devices/$DID/geofences -H "$J" -H "Authorization: Bearer $A" -d '{"geofences":[{"id":0,"name":"Truong","lat":10.77,"lng":106.7,"radiusM":150}],"expectedVersion":0}'
curl -s -o /dev/null -w "put gf stale (expect 409) %{http_code}\n" -X PUT $B/api/devices/$DID/geofences -H "$J" -H "Authorization: Bearer $A" -d '{"geofences":[],"expectedVersion":0}'
GID=$(curl -s $B/api/devices/me/geofences -H "Authorization: Bearer $DT" | py "['geofences'][0]['id']")
curl -s -o /dev/null -w "ev post %{http_code}\n" -X POST $B/api/devices/me/geofence-events -H "$J" -H "Authorization: Bearer $DT" -d "{\"events\":[{\"geofenceId\":$GID,\"type\":\"exit\",\"time\":\"$NOW\"}]}"
curl -s -w "\nev get %{http_code}\n" $B/api/devices/$DID/geofence-events -H "Authorization: Bearer $A"
curl -s -o /dev/null -w "ev bad type (expect 400) %{http_code}\n" -X POST $B/api/devices/me/geofence-events -H "$J" -H "Authorization: Bearer $DT" -d "{\"events\":[{\"geofenceId\":$GID,\"type\":\"x\",\"time\":\"$NOW\"}]}"
curl -s -o /dev/null -w "device token on parent route (expect 403) %{http_code}\n" $B/api/devices/$DID/location -H "Authorization: Bearer $DT"
curl -s -o /dev/null -w "no token (expect 401) %{http_code}\n" $B/api/devices/me/geofences
# --- Quyền riêng tư vị trí (API-11) ---
code() { curl -s -o /dev/null -w "$1 (expect $2) %{http_code}\n" "${@:3}"; }
echo "settings default (expect locationSharing True): $(curl -s $B/api/devices/me/settings -H "Authorization: Bearer $DT" | py "['locationSharing']")"
echo "parent sharing default (expect True): $(curl -s $B/api/devices/$DID/location-sharing -H "Authorization: Bearer $A" | py "['enabled']")"
code "put sharing no body field" 400 -X PUT $B/api/devices/$DID/location-sharing -H "$J" -H "Authorization: Bearer $A" -d '{}'
code "put sharing wrong type" 400 -X PUT $B/api/devices/$DID/location-sharing -H "$J" -H "Authorization: Bearer $A" -d '{"enabled":"no"}'
echo "sharing still on after bad puts (expect True): $(curl -s $B/api/devices/$DID/location-sharing -H "Authorization: Bearer $A" | py "['enabled']")"
EB=$(curl -s -X POST $B/api/auth/register -H "$J" -d "{\"email\":\"o$RANDOM@x.com\",\"password\":\"password123\"}" | py "['accessToken']")
code "other family get sharing" 404 $B/api/devices/$DID/location-sharing -H "Authorization: Bearer $EB"
code "other family put sharing" 404 -X PUT $B/api/devices/$DID/location-sharing -H "$J" -H "Authorization: Bearer $EB" -d '{"enabled":false}'
code "other family delete locations" 404 -X DELETE $B/api/devices/$DID/locations -H "Authorization: Bearer $EB"
code "device token put sharing" 403 -X PUT $B/api/devices/$DID/location-sharing -H "$J" -H "Authorization: Bearer $DT" -d '{"enabled":false}'
code "parent token on settings" 403 $B/api/devices/me/settings -H "Authorization: Bearer $A"
code "put sharing off" 200 -X PUT $B/api/devices/$DID/location-sharing -H "$J" -H "Authorization: Bearer $A" -d '{"enabled":false}'
echo "settings after off (expect False): $(curl -s $B/api/devices/me/settings -H "Authorization: Bearer $DT" | py "['locationSharing']")"
code "child post while off" 403 -X POST $B/api/devices/me/locations -H "$J" -H "Authorization: Bearer $DT" -d "{\"points\":[{\"lat\":10.78,\"lng\":106.71,\"accuracy\":9,\"time\":\"$NOW\"}]}"
curl -s -w "\nparent last location while off (expect 403 + locationSharing false) %{http_code}\n" $B/api/devices/$DID/location -H "Authorization: Bearer $A"
code "parent history while off" 403 $B/api/devices/$DID/locations -H "Authorization: Bearer $A"
code "put sharing on" 200 -X PUT $B/api/devices/$DID/location-sharing -H "$J" -H "Authorization: Bearer $A" -d '{"enabled":true}'
echo "history count after on (expect 1 = only the point sent before off): $(curl -s $B/api/devices/$DID/locations -H "Authorization: Bearer $A" | python -c "import sys,json;print(len(json.load(sys.stdin)))")"
code "delete locations" 204 -X DELETE $B/api/devices/$DID/locations -H "Authorization: Bearer $A"
echo "history count after delete (expect 0): $(curl -s $B/api/devices/$DID/locations -H "Authorization: Bearer $A" | python -c "import sys,json;print(len(json.load(sys.stdin)))")"
code "last location after delete" 204 $B/api/devices/$DID/location -H "Authorization: Bearer $A"
# --- Policy (API-04): server chỉ kiểm tra JSON hợp lệ + kích thước, lưu nguyên khối ---
P='{"schemaVersion":1,"timeLimit":{"enabled":true},"appLock":{"blocked":["com.google.android.youtube"],"schedules":[]}}'
pj() { python -c "import json,sys;print(json.dumps({'json':sys.argv[1],'expectedVersion':int(sys.argv[2])}))" "$1" "$2"; }
curl -s -o /dev/null -w "policy put v0 (expect 200) %{http_code}\n" -X PUT $B/api/devices/$DID/policy -H "$J" -H "Authorization: Bearer $A" -d "$(pj "$P" 0)"
curl -s -o /dev/null -w "policy put stale (expect 409) %{http_code}\n" -X PUT $B/api/devices/$DID/policy -H "$J" -H "Authorization: Bearer $A" -d "$(pj "$P" 0)"
curl -s -o /dev/null -w "policy bad json (expect 400) %{http_code}\n" -X PUT $B/api/devices/$DID/policy -H "$J" -H "Authorization: Bearer $A" -d "$(pj '{khong phai json' 1)"
curl -s -o /dev/null -w "policy array root (expect 400) %{http_code}\n" -X PUT $B/api/devices/$DID/policy -H "$J" -H "Authorization: Bearer $A" -d "$(pj '[1,2]' 1)"
python -c "import json;print(json.dumps({'json':json.dumps({'x':'a'*70000}),'expectedVersion':1}))" | curl -s -o /dev/null -w "policy too big (expect 400) %{http_code}
" -X PUT $B/api/devices/$DID/policy -H "$J" -H "Authorization: Bearer $A" -d @-
echo "child reads policy (expect version 1, same block):"
curl -s $B/api/devices/me/policy -H "Authorization: Bearer $DT"; echo
# --- LiÃªn há»‡ kháº©n cáº¥p SOS trong policy (API-13): tá»‘i Ä‘a 3, nhÃ£n 1-30, sá»‘ 9-12 chá»¯ sá»‘ ---
cj() { python -c "import json,sys;print(json.dumps({'json':json.dumps({'schemaVersion':2,'contacts':json.loads(sys.argv[1])}),'expectedVersion':int(sys.argv[2])}))" "$1" "$2"; }
cput() { code "$1" "$2" -X PUT $B/api/devices/$DID/policy -H "$J" -H "Authorization: Bearer $A" -d "$(cj "$3" "$4")"; }
cput "contacts 4 entries" 400 '[{"label":"a","phone":"0901234567"},{"label":"b","phone":"0901234567"},{"label":"c","phone":"0901234567"},{"label":"d","phone":"0901234567"}]' 1
cput "contacts not array" 400 '"0901234567"' 1
cput "contacts entry not object" 400 '["0901234567"]' 1
cput "contacts phone letters" 400 '[{"label":"Me","phone":"09012abc67"}]' 1
cput "contacts phone too short" 400 '[{"label":"Me","phone":"12345678"}]' 1
cput "contacts phone too long" 400 '[{"label":"Me","phone":"1234567890123"}]' 1
cput "contacts phone number type" 400 '[{"label":"Me","phone":901234567}]' 1
cput "contacts label empty" 400 '[{"label":"  ","phone":"0901234567"}]' 1
cput "contacts label 31 chars" 400 "[{\"label\":\"$(python -c "print('a'*31)")\",\"phone\":\"0901234567\"}]" 1
cput "contacts label control char" 400 '[{"label":"a\nb","phone":"0901234567"}]' 1
cput "contacts missing phone" 400 '[{"label":"Me"}]' 1
cput "contacts sos string" 400 '[{"label":"Me","phone":"0901234567","sos":"yes"}]' 1
echo "policy version unchanged after bad contacts (expect 1): $(curl -s $B/api/devices/$DID/policy -H "Authorization: Bearer $A" | py "['version']")"
cput "contacts empty list ok" 200 '[]' 1
cput "contacts 3 entries ok (label 30 chars, +84)" 200 "[{\"label\":\"$(python -c "print('a'*30)")\",\"phone\":\"+84901234567\",\"sos\":true},{\"label\":\"Bo\",\"phone\":\"0901234568\"},{\"label\":\"Cap cuu\",\"phone\":\"0901234569\",\"sos\":true}]" 2
echo "child reads contacts (expect 3): $(curl -s $B/api/devices/me/policy -H "Authorization: Bearer $DT" | python -c "import sys,json;print(len(json.loads(json.load(sys.stdin)['json'])['contacts']))")"
code "contacts other family" 404 -X PUT $B/api/devices/$DID/policy -H "$J" -H "Authorization: Bearer $EB" -d "$(cj '[]' 3)"
code "contacts device token" 403 -X PUT $B/api/devices/$DID/policy -H "$J" -H "Authorization: Bearer $DT" -d "$(cj '[]' 3)"
# --- Lệnh từ xa (API-05): danh sách Type cho phép + kiểm payload ---
cmd() { python -c "import json,sys;print(json.dumps({'type':sys.argv[1],'payloadJson':sys.argv[2]} if sys.argv[2]!='-' else {'type':sys.argv[1]}))" "$1" "$2" | curl -s -o /dev/null -w "$3 (expect $4) %{http_code}\n" -X POST $B/api/devices/$DID/commands -H "$J" -H "Authorization: Bearer $A" -d @-; }
cmd app_unlock_temp '{"package":"com.google.android.youtube","minutes":15}' "unlock_temp ok" 200
cmd app_relock '{"package":"com.google.android.youtube"}' "relock ok" 200
cmd app_block '{"package":"com.zing.zalo"}' "block ok" 200
cmd app_allow '{"package":"com.zing.zalo"}' "allow ok" 200
cmd pause '{"minutes":30}' "pause ok" 200
cmd unpause - "unpause no payload ok" 200
cmd abc '{}' "unknown type" 400
cmd app_unlock_temp '{"package":"com.google.android.youtube"}' "unlock_temp no minutes" 400
cmd app_unlock_temp '{"package":"com.google.android.youtube","minutes":0}' "unlock_temp minutes 0" 400
cmd app_unlock_temp '{"package":"com.google.android.youtube","minutes":241}' "unlock_temp minutes 241" 400
cmd app_unlock_temp '{"package":"com.google.android.youtube","minutes":"15"}' "unlock_temp minutes string" 400
cmd app_unlock_temp '{"package":"khong co cham","minutes":5}' "unlock_temp bad package" 400
cmd app_block '{}' "block no package" 400
cmd app_block 'khong phai json' "payload not json" 400
cmd app_block '[1]' "payload array" 400
cmd pause '{"minutes":99999}' "pause minutes too big" 400
python -c "import json;print(json.dumps({'type':'pause','payloadJson':json.dumps({'minutes':5,'x':'a'*5000})}))" | curl -s -o /dev/null -w "payload too big (expect 400) %{http_code}\n" -X POST $B/api/devices/$DID/commands -H "$J" -H "Authorization: Bearer $A" -d @-
echo "child pending commands (expect 6 valid ones, ids ascending):"
curl -s $B/api/devices/me/commands -H "Authorization: Bearer $DT" | python -c "import sys,json;print([c['type'] for c in json.load(sys.stdin)])"
# --- Trạng thái máy con (API-09) ---
st() { python -c "import json,sys;print(json.dumps(json.loads(sys.argv[1])))" "$1" | curl -s -o /dev/null -w "$2 (expect $3) %{http_code}\n" -X PUT $B/api/devices/me/status -H "$J" -H "Authorization: Bearer $DT" -d @-; }
echo "status before any report (expect reportedAt null, defaults):"
curl -s $B/api/devices/$DID/status -H "Authorization: Bearer $A"; echo
SOON=$(python -c "import datetime as d;print((d.datetime.utcnow()+d.timedelta(minutes=30)).strftime('%Y-%m-%dT%H:%M:%SZ'))")
PAST=$(python -c "import datetime as d;print((d.datetime.utcnow()-d.timedelta(minutes=30)).strftime('%Y-%m-%dT%H:%M:%SZ'))")
FAR=$(python -c "import datetime as d;print((d.datetime.utcnow()+d.timedelta(days=2)).strftime('%Y-%m-%dT%H:%M:%SZ'))")
st "{\"batteryPercent\":40,\"policyVersion\":1,\"isPaused\":true,\"studyActive\":false,\"permissionsMissing\":[\"accessibility\",\"device_admin\"],\"appVersion\":\"1.0.0+1\",\"tempUnlocked\":[{\"package\":\"com.google.android.youtube\",\"until\":\"$SOON\"},{\"package\":\"com.zing.zalo\",\"until\":\"$PAST\"}]}" "status put ok" 204
echo "mother reads status (expect isPaused true, battery 40, 2 perms, only youtube unlocked - expired zalo filtered):"
curl -s $B/api/devices/$DID/status -H "Authorization: Bearer $A"; echo
st '{"policyVersion":1,"isPaused":false,"studyActive":false}' "status put minimal (no battery) ok" 204
curl -s $B/api/devices/$DID/status -H "Authorization: Bearer $A" | python -c "import sys,json;d=json.load(sys.stdin);print('overwrite:',d['isPaused'],d['batteryPercent'],d['permissionsMissing'],d['tempUnlocked'])"
st '{"batteryPercent":101,"policyVersion":1,"isPaused":false,"studyActive":false}' "battery 101" 400
st '{"batteryPercent":-1,"policyVersion":1,"isPaused":false,"studyActive":false}' "battery -1" 400
st '{"batteryPercent":"abc","policyVersion":1,"isPaused":false,"studyActive":false}' "battery string" 400
st '{"policyVersion":-1,"isPaused":false,"studyActive":false}' "policyVersion -1" 400
st '{"policyVersion":1,"isPaused":"yes","studyActive":false}' "isPaused string" 400
st "{\"policyVersion\":1,\"isPaused\":false,\"studyActive\":false,\"appVersion\":\"$(python -c "print('1'*33)")\"}" "appVersion 33 chars" 400
st '{"policyVersion":1,"isPaused":false,"studyActive":false,"appVersion":"1.0 <script>"}' "appVersion bad chars" 400
st '{"policyVersion":1,"isPaused":false,"studyActive":false,"permissionsMissing":["Accessibility"]}' "permission uppercase" 400
st "{\"policyVersion\":1,\"isPaused\":false,\"studyActive\":false,\"permissionsMissing\":[\"$(python -c "print('a'*41)")\"]}" "permission 41 chars" 400
st "{\"policyVersion\":1,\"isPaused\":false,\"studyActive\":false,\"permissionsMissing\":$(python -c "import json;print(json.dumps(['p%d'%i for i in range(21)]))")}" "21 permissions" 400
st '{"policyVersion":1,"isPaused":false,"studyActive":false,"tempUnlocked":[{"package":"khong co cham","until":"'$SOON'"}]}' "temp bad package" 400
st '{"policyVersion":1,"isPaused":false,"studyActive":false,"tempUnlocked":[{"package":"com.a.b","until":"'$FAR'"}]}' "temp until 2 days ahead" 400
st "{\"policyVersion\":1,\"isPaused\":false,\"studyActive\":false,\"tempUnlocked\":$(python -c "import json;print(json.dumps([{'package':'com.a.p%d'%i,'until':'$SOON'} for i in range(51)]))")}" "51 temp unlocked" 400
st '{"policyVersion":1,"isPaused":false,"studyActive":false,"tempUnlocked":[{"package":"com.a.b"}]}' "temp missing until" 400
curl -s -o /dev/null -w "status put no token (expect 401) %{http_code}\n" -X PUT $B/api/devices/me/status -H "$J" -d '{"policyVersion":1,"isPaused":false,"studyActive":false}'
curl -s -o /dev/null -w "status put with parent token (expect 403) %{http_code}\n" -X PUT $B/api/devices/me/status -H "$J" -H "Authorization: Bearer $A" -d '{"policyVersion":1,"isPaused":false,"studyActive":false}'
curl -s -o /dev/null -w "status get with device token (expect 403) %{http_code}\n" $B/api/devices/$DID/status -H "Authorization: Bearer $DT"
curl -s -o /dev/null -w "status get other device id (expect 404) %{http_code}\n" $B/api/devices/999999/status -H "Authorization: Bearer $A"
# Mẹ khác gia đình không đọc được trạng thái máy con của gia đình này
E2="o$RANDOM@x.com"; A2=$(curl -s -X POST $B/api/auth/register -H "$J" -d "{\"email\":\"$E2\",\"password\":\"password123\"}" | py "['accessToken']")
curl -s -o /dev/null -w "status get from another family (expect 404) %{http_code}\n" $B/api/devices/$DID/status -H "Authorization: Bearer $A2"
curl -s -o /dev/null -w "commands get from another family (expect 404) %{http_code}\n" $B/api/devices/$DID/commands -H "Authorization: Bearer $A2"
echo "commands list (mother) has createdAt/doneAt:"
curl -s $B/api/devices/$DID/commands -H "Authorization: Bearer $A" | python -c "import sys,json;d=json.load(sys.stdin);print(len(d),sorted(d[0].keys()))"
# --- Duyệt app mới cài (API-07) ---
ap() { python -c "import json,sys;print(json.dumps(json.loads(sys.argv[1])))" "$1" | curl -s -o /dev/null -w "$2 (expect $3) %{http_code}\n" -X POST $B/api/devices/me/apps -H "$J" -H "Authorization: Bearer $DT" -d @-; }
apps() { curl -s "$B/api/devices/$DID/apps$1" -H "Authorization: Bearer $A" | python -c "import sys,json;print(sorted((a['packageName'],a['status']) for a in json.load(sys.stdin)))"; }
ap '{"apps":[{"packageName":"com.game.vui","label":"Game vui","isNew":true},{"packageName":"com.tiktok.x","label":"TikTok","isNew":true},{"packageName":"com.old.app","label":"App cu"}]}' "apps post ok" 204
echo "mother lists new (expect game + tiktok):"; apps "?status=new"
echo "mother lists all (expect 3, com.old.app allowed):"; apps ""
ap '{"apps":[{"packageName":"khong co cham","label":"x"}]}' "apps bad package" 400
ap '{"apps":[{"packageName":"com.a.b","label":""}]}' "apps empty label" 400
ap "{\"apps\":[{\"packageName\":\"com.a.b\",\"label\":\"$(python -c "print('a'*201)")\"}]}" "apps label 201 chars" 400
ap "{\"apps\":[{\"packageName\":\"com.$(python -c "print('a'*200)").b\",\"label\":\"x\"}]}" "apps package > 200 chars" 400
ap '{"apps":[{"packageName":"com.a.b","label":"x","isNew":"yes"}]}' "apps isNew string" 400
ap '{"apps":"abc"}' "apps not a list" 400
ap '{}' "apps missing" 400
python -c "import json;print(json.dumps({'apps':[{'packageName':'com.a.p%d'%i,'label':'x'} for i in range(2001)]}))" | curl -s -o /dev/null -w "apps 2001 items (expect 400) %{http_code}
" -X POST $B/api/devices/me/apps -H "$J" -H "Authorization: Bearer $DT" -d @-
curl -s -o /dev/null -w "apps post with parent token (expect 403) %{http_code}\n" -X POST $B/api/devices/me/apps -H "$J" -H "Authorization: Bearer $A" -d '{"apps":[]}'
curl -s -o /dev/null -w "apps post no token (expect 401) %{http_code}\n" -X POST $B/api/devices/me/apps -H "$J" -d '{"apps":[]}'
curl -s -o /dev/null -w "list bad status (expect 400) %{http_code}\n" "$B/api/devices/$DID/apps?status=abc" -H "Authorization: Bearer $A"
curl -s -o /dev/null -w "list with device token (expect 403) %{http_code}\n" "$B/api/devices/$DID/apps" -H "Authorization: Bearer $DT"
curl -s -o /dev/null -w "list from another family (expect 404) %{http_code}\n" "$B/api/devices/$DID/apps?status=new" -H "Authorization: Bearer $A2"
setapp() { curl -s -o /dev/null -w "$3 (expect $4) %{http_code}\n" -X PUT "$B/api/devices/$DID/apps/$1" -H "$J" -H "Authorization: Bearer $A" -d "$2"; }
setapp com.game.vui '{"status":"new"}' "set status new (mother cannot)" 400
setapp com.game.vui '{"status":"maybe"}' "set status invalid" 400
setapp com.game.vui '{}' "set status missing" 400
setapp com.game.vui '{"status":5}' "set status number" 400
setapp khong.co-cham '{"status":"allowed"}' "set bad package" 400
setapp com.chua.tung.bao '{"status":"allowed"}' "set package never reported" 404
curl -s -o /dev/null -w "set from another family (expect 404) %{http_code}\n" -X PUT $B/api/devices/$DID/apps/com.game.vui -H "$J" -H "Authorization: Bearer $A2" -d '{"status":"allowed"}'
curl -s -o /dev/null -w "set with device token (expect 403) %{http_code}\n" -X PUT $B/api/devices/$DID/apps/com.game.vui -H "$J" -H "Authorization: Bearer $DT" -d '{"status":"allowed"}'
curl -s -o /dev/null -w "set no token (expect 401) %{http_code}\n" -X PUT $B/api/devices/$DID/apps/com.game.vui -H "$J" -d '{"status":"allowed"}'
curl -s -o /dev/null -w "set unknown device (expect 404) %{http_code}\n" -X PUT $B/api/devices/999999/apps/com.game.vui -H "$J" -H "Authorization: Bearer $A" -d '{"status":"allowed"}'
echo "still new after bad attempts (expect game + tiktok):"; apps "?status=new"
dsc() { curl -s $B/api/devices/me/apps/decisions -H "Authorization: Bearer $DT" | python -c "import sys,json;print(sorted((a['packageName'],a['status']) for a in json.load(sys.stdin)))"; }
echo "child decisions before any decision (expect []):"; dsc
setapp com.game.vui '{"status":"allowed"}' "allow game" 200
setapp com.tiktok.x '{"status":"blocked"}' "block tiktok" 200
echo "child decisions (expect game allowed, tiktok blocked; no com.old.app):"; dsc
echo "mother new list (expect []):"; apps "?status=new"
echo "mother blocked list (expect tiktok):"; apps "?status=blocked"
ap '{"apps":[{"packageName":"com.game.vui","label":"Game vui 2"}]}' "repost without isNew keeps decision" 204
echo "decisions after plain repost (expect still game allowed + tiktok blocked):"; dsc
ap '{"apps":[{"packageName":"com.game.vui","label":"Game vui","isNew":true}]}' "reinstall isNew resets" 204
echo "decisions after reinstall (expect only tiktok blocked), mother new (expect game):"; dsc; apps "?status=new"
curl -s -o /dev/null -w "decisions with parent token (expect 403) %{http_code}\n" $B/api/devices/me/apps/decisions -H "Authorization: Bearer $A"
curl -s -o /dev/null -w "decisions no token (expect 401) %{http_code}\n" $B/api/devices/me/apps/decisions
# --- Yêu cầu của máy con (API-06) ---
rq() { python -c "import json,sys;print(json.dumps({'kind':sys.argv[1],'payloadJson':sys.argv[2]} if sys.argv[2]!='-' else {'kind':sys.argv[1]}))" "$1" "$2" | curl -s -o /dev/null -w "$3 (expect $4) %{http_code}\n" -X POST $B/api/devices/me/requests -H "$J" -H "Authorization: Bearer $DT" -d @-; }
rq extra_time '{"minutes":0}' "extra_time minutes 0" 400
rq extra_time '{"minutes":241}' "extra_time minutes 241" 400
rq extra_time '{"minutes":"15"}' "extra_time minutes string" 400
rq extra_time '{"minutes":1.5}' "extra_time minutes decimal" 400
rq extra_time '{}' "extra_time no minutes" 400
rq extra_time - "extra_time no payload" 400
rq extra_time '{"minutes":15,"app":"com.zing.zalo"}' "extra_time extra field (privacy)" 400
rq study_done '{"minutes":5}' "study_done with field" 400
rq study_done '[1]' "study_done array" 400
rq study_done 'khong phai json' "payload not json" 400
rq abc '{}' "unknown kind" 400
rq "" '{}' "empty kind" 400
python -c "import json;print(json.dumps({'kind':'extra_time','payloadJson':json.dumps({'minutes':15,'x':'a'*300})}))" | curl -s -o /dev/null -w "payload too big (expect 400) %{http_code}\n" -X POST $B/api/devices/me/requests -H "$J" -H "Authorization: Bearer $DT" -d @-
python -c "import json;print(json.dumps({'kind':'x'*21,'payloadJson':'{}'}))" | curl -s -o /dev/null -w "kind 21 chars (expect 400) %{http_code}\n" -X POST $B/api/devices/me/requests -H "$J" -H "Authorization: Bearer $DT" -d @-
curl -s -o /dev/null -w "kind wrong type (expect 400) %{http_code}\n" -X POST $B/api/devices/me/requests -H "$J" -H "Authorization: Bearer $DT" -d '{"kind":5}'
curl -s -o /dev/null -w "request with parent token (expect 403) %{http_code}\n" -X POST $B/api/devices/me/requests -H "$J" -H "Authorization: Bearer $A" -d '{"kind":"study_done"}'
curl -s -o /dev/null -w "request no token (expect 401) %{http_code}\n" -X POST $B/api/devices/me/requests -H "$J" -d '{"kind":"study_done"}'
R1=$(curl -s -X POST $B/api/devices/me/requests -H "$J" -H "Authorization: Bearer $DT" -d '{"kind":"extra_time","payloadJson":"{\"minutes\":30}"}')
echo "extra_time create (expect pending, minutes 30): $R1"
RID=$(echo $R1 | py "['id']")
curl -s -w "\nduplicate pending (expect 409 with same id $RID) %{http_code}\n" -X POST $B/api/devices/me/requests -H "$J" -H "Authorization: Bearer $DT" -d '{"kind":"extra_time","payloadJson":"{\"minutes\":15}"}'
echo "child reads own request (expect pending):"; curl -s $B/api/devices/me/requests/$RID -H "Authorization: Bearer $DT" | py "['status']"
echo "mother lists pending (expect 1 extra_time):"; curl -s "$B/api/devices/$DID/requests?status=pending" -H "Authorization: Bearer $A" | python -c "import sys,json;print([(r['kind'],r['status']) for r in json.load(sys.stdin)])"
curl -s -o /dev/null -w "list bad status (expect 400) %{http_code}\n" "$B/api/devices/$DID/requests?status=abc" -H "Authorization: Bearer $A"
curl -s -o /dev/null -w "list with device token (expect 403) %{http_code}\n" "$B/api/devices/$DID/requests" -H "Authorization: Bearer $DT"
# Gia đình khác: không đọc/duyệt được (404)
E2="u$RANDOM@x.com"; A2=$(curl -s -X POST $B/api/auth/register -H "$J" -d "{\"email\":\"$E2\",\"password\":\"password123\"}" | py "['accessToken']")
CODE2=$(curl -s -X POST $B/api/pairing/code -H "$J" -H "Authorization: Bearer $A2" -d '{"deviceName":"Con2"}' | py "['code']")
DT2=$(curl -s -X POST $B/api/pairing/claim -H "$J" -d "{\"code\":\"$CODE2\"}" | py "['deviceToken']")
curl -s -o /dev/null -w "other family list (expect 404) %{http_code}\n" "$B/api/devices/$DID/requests" -H "Authorization: Bearer $A2"
curl -s -o /dev/null -w "other family approve (expect 404) %{http_code}\n" -X PUT $B/api/requests/$RID -H "$J" -H "Authorization: Bearer $A2" -d '{"decision":"approved"}'
curl -s -o /dev/null -w "other child reads my request (expect 404) %{http_code}\n" $B/api/devices/me/requests/$RID -H "Authorization: Bearer $DT2"
curl -s -o /dev/null -w "unknown request (expect 404) %{http_code}\n" -X PUT $B/api/requests/999999 -H "$J" -H "Authorization: Bearer $A" -d '{"decision":"approved"}'
curl -s -o /dev/null -w "approve with device token (expect 403) %{http_code}\n" -X PUT $B/api/requests/$RID -H "$J" -H "Authorization: Bearer $DT" -d '{"decision":"approved"}'
curl -s -o /dev/null -w "approve no token (expect 401) %{http_code}\n" -X PUT $B/api/requests/$RID -H "$J" -d '{"decision":"approved"}'
dec() { curl -s -o /dev/null -w "$3 (expect $4) %{http_code}\n" -X PUT $B/api/requests/$1 -H "$J" -H "Authorization: Bearer $A" -d "$2"; }
dec $RID '{"decision":"maybe"}' "decision invalid" 400
dec $RID '{}' "decision missing" 400
dec $RID '{"decision":"approved","minutes":0}' "approve minutes 0" 400
dec $RID '{"decision":"approved","minutes":121}' "approve minutes 121" 400
dec $RID '{"decision":"rejected","minutes":10}' "reject with minutes" 400
dec $RID '{"decision":"approved","minutes":"x"}' "approve minutes string" 400
echo "still pending after bad attempts (expect pending):"; curl -s $B/api/devices/me/requests/$RID -H "Authorization: Bearer $DT" | py "['status']"
dec $RID '{"decision":"approved","minutes":20}' "approve with 20 min override" 200
dec $RID '{"decision":"rejected"}' "decide twice" 409
echo "child sees approved:"; curl -s $B/api/devices/me/requests/$RID -H "Authorization: Bearer $DT" | python -c "import sys,json;d=json.load(sys.stdin);print(d['status'],d['decidedAt'] is not None)"
echo "child commands (expect last = extra_time_grant minutes 20):"; curl -s $B/api/devices/me/commands -H "Authorization: Bearer $DT" | python -c "import sys,json;c=json.load(sys.stdin)[-1];print(c['type'],c['payloadJson'])"
R2=$(curl -s -X POST $B/api/devices/me/requests -H "$J" -H "Authorization: Bearer $DT" -d '{"kind":"study_done"}'); RID2=$(echo $R2 | py "['id']")
curl -s -o /dev/null -w "new extra_time after decided allowed (expect 200) %{http_code}\n" -X POST $B/api/devices/me/requests -H "$J" -H "Authorization: Bearer $DT" -d '{"kind":"extra_time","payloadJson":"{\"minutes\":5}"}'
curl -s -o /dev/null -w "study_done duplicate (expect 409) %{http_code}\n" -X POST $B/api/devices/me/requests -H "$J" -H "Authorization: Bearer $DT" -d '{"kind":"study_done"}'
dec $RID2 '{"decision":"approved","minutes":5}' "approve study_done with minutes" 400
dec $RID2 '{"decision":"rejected"}' "reject study_done" 200
echo "child commands (expect last = study_reject):"; curl -s $B/api/devices/me/commands -H "Authorization: Bearer $DT" | python -c "import sys,json;print(json.load(sys.stdin)[-1]['type'])"
RID4=$(curl -s "$B/api/devices/$DID/requests?status=pending" -H "Authorization: Bearer $A" | python -c "import sys,json;print([r['id'] for r in json.load(sys.stdin) if r['kind']=='extra_time'][0])")
N0=$(curl -s $B/api/devices/me/commands -H "Authorization: Bearer $DT" | python -c "import sys,json;print(len(json.load(sys.stdin)))")
dec $RID4 '{"decision":"rejected"}' "reject extra_time" 200
N1=$(curl -s $B/api/devices/me/commands -H "Authorization: Bearer $DT" | python -c "import sys,json;print(len(json.load(sys.stdin)))")
echo "commands before/after reject extra_time (expect equal): $N0 $N1"
echo "child sees rejected:"; curl -s $B/api/devices/me/requests/$RID4 -H "Authorization: Bearer $DT" | py "['status']"
# --- Báo cáo sử dụng (API-08): phút theo app theo ngày, upsert, kiểm từng trường, cô lập gia đình ---
dt() { python -c "import datetime as d,sys;print((d.datetime.utcnow()+d.timedelta(days=int(sys.argv[1]))).strftime('%Y-%m-%d'))" "$1"; }
D0=$(dt 0); D1=$(dt -1); D2=$(dt -2); DF=$(dt 5); DOLD=$(dt -100)
up() { # $1 = JSON, $2 = nhãn, $3 = mã mong đợi
  python -c "import json,sys;print(json.dumps(json.loads(sys.argv[1])))" "$1" | curl -s -o /dev/null -w "$2 (expect $3) %{http_code}\n" -X POST $B/api/devices/me/usage -H "$J" -H "Authorization: Bearer $DT" -d @-
}
up "{\"days\":[{\"date\":\"$D1\",\"totalMinutes\":90,\"blocks\":2,\"apps\":{\"com.google.android.youtube\":60,\"com.zing.zalo\":30}},{\"date\":\"$D0\",\"totalMinutes\":40,\"blocks\":0,\"apps\":{\"com.google.android.youtube\":40}}]}" "usage post 2 days" 204
echo "mother reads usage (expect 2 days, ascending, youtube 60 then 40):"
curl -s "$B/api/devices/$DID/usage?from=$D2&to=$D0" -H "Authorization: Bearer $A" | python -c "import sys,json;print([(d['date'],d['totalMinutes'],d['blocks'],d['apps']) for d in json.load(sys.stdin)])"
up "{\"days\":[{\"date\":\"$D0\",\"totalMinutes\":55,\"blocks\":1,\"apps\":{\"com.zing.zalo\":55}}]}" "usage resend same day (upsert)" 204
echo "after upsert (expect D0 total 55 only zalo, D1 unchanged, still 2 rows):"
curl -s "$B/api/devices/$DID/usage?from=$D2&to=$D0" -H "Authorization: Bearer $A" | python -c "import sys,json;d=json.load(sys.stdin);print(len(d),[(x['totalMinutes'],x['apps']) for x in d])"
echo "default range (no from/to) returns 7-day window:"; curl -s "$B/api/devices/$DID/usage" -H "Authorization: Bearer $A" | python -c "import sys,json;print(len(json.load(sys.stdin)))"
up '{"days":[]}' "usage empty batch" 400
up '{}' "usage missing days" 400
up '{"days":"x"}' "usage days wrong type" 400
up "{\"days\":[{\"date\":\"$D0\",\"totalMinutes\":\"abc\",\"blocks\":0,\"apps\":{}}]}" "usage minutes string" 400
up "{\"days\":[{\"date\":\"$D0\",\"totalMinutes\":1441,\"blocks\":0,\"apps\":{}}]}" "usage total 1441" 400
up "{\"days\":[{\"date\":\"$D0\",\"totalMinutes\":-1,\"blocks\":0,\"apps\":{}}]}" "usage total -1" 400
up "{\"days\":[{\"date\":\"$D0\",\"totalMinutes\":10,\"blocks\":-1,\"apps\":{}}]}" "usage blocks -1" 400
up "{\"days\":[{\"date\":\"$D0\",\"totalMinutes\":10,\"blocks\":10001,\"apps\":{}}]}" "usage blocks 10001" 400
up "{\"days\":[{\"date\":\"$D0\",\"totalMinutes\":10,\"blocks\":0,\"apps\":{\"com.a.b\":1441}}]}" "usage app minutes 1441" 400
up "{\"days\":[{\"date\":\"$D0\",\"totalMinutes\":10,\"blocks\":0,\"apps\":{\"com.a.b\":-5}}]}" "usage app minutes -5" 400
up "{\"days\":[{\"date\":\"$D0\",\"totalMinutes\":10,\"blocks\":0,\"apps\":{\"khong co cham\":5}}]}" "usage bad package" 400
up "{\"days\":[{\"date\":\"$D0\",\"totalMinutes\":10,\"blocks\":0,\"apps\":{\"com.a.b<script>\":5}}]}" "usage package with chars" 400
up "{\"days\":[{\"date\":\"$D0\",\"totalMinutes\":10,\"blocks\":0,\"apps\":{\"com.$(python -c "print('a'*201)")\":5}}]}" "usage package 201+ chars" 400
up "{\"days\":[{\"date\":\"$D0\",\"totalMinutes\":10,\"blocks\":0,\"apps\":$(python -c "import json;print(json.dumps({'com.a.p%d'%i:1 for i in range(201)}))")}]}" "usage 201 apps in a day" 400
up "{\"days\":[{\"date\":\"$D0\",\"totalMinutes\":10,\"blocks\":0,\"apps\":$(python -c "import json;print(json.dumps({'com.a.p%d'%i:1 for i in range(200)}))")}]}" "usage exactly 200 apps" 204
up "{\"days\":[{\"date\":\"$DF\",\"totalMinutes\":10,\"blocks\":0,\"apps\":{}}]}" "usage date 5 days ahead" 400
up "{\"days\":[{\"date\":\"$DOLD\",\"totalMinutes\":10,\"blocks\":0,\"apps\":{}}]}" "usage date 100 days old" 400
up '{"days":[{"date":"2026-13-45","totalMinutes":10,"blocks":0,"apps":{}}]}' "usage date invalid" 400
up '{"days":[{"date":"31/10/2026","totalMinutes":10,"blocks":0,"apps":{}}]}' "usage date wrong format" 400
up "{\"days\":[{\"date\":\"$D0\",\"totalMinutes\":10,\"blocks\":0,\"apps\":{}},{\"date\":\"$D0\",\"totalMinutes\":20,\"blocks\":0,\"apps\":{}}]}" "usage duplicate date in batch" 400
up "{\"days\":$(python -c "import json,datetime as d;print(json.dumps([{'date':(d.date.today()-d.timedelta(days=i)).isoformat(),'totalMinutes':1,'blocks':0,'apps':{}} for i in range(32)]))")}" "usage 32 days" 400
up "{\"days\":$(python -c "import json,datetime as d;print(json.dumps([{'date':(d.date.today()-d.timedelta(days=i)).isoformat(),'totalMinutes':1,'blocks':0,'apps':{}} for i in range(31)]))")}" "usage exactly 31 days" 204
echo "D0 after the 31-day batch overwrote it (expect 1 0 = total 1, no apps):"
curl -s "$B/api/devices/$DID/usage?from=$D0&to=$D0" -H "Authorization: Bearer $A" | python -c "import sys,json;d=json.load(sys.stdin)[0];print(d['totalMinutes'],len(d['apps']))"
python -c "import json;print(json.dumps({'days':[{'date':'$D0','totalMinutes':1,'blocks':0,'apps':{'com.a.b':1},'x':'a'*1000}]}))" | curl -s -o /dev/null -w "usage extra field ignored (expect 204) %{http_code}\n" -X POST $B/api/devices/me/usage -H "$J" -H "Authorization: Bearer $DT" -d @-
curl -s -o /dev/null -w "usage bad from (expect 400) %{http_code}\n" "$B/api/devices/$DID/usage?from=abc" -H "Authorization: Bearer $A"
curl -s -o /dev/null -w "usage bad to (expect 400) %{http_code}\n" "$B/api/devices/$DID/usage?to=2026-02-30" -H "Authorization: Bearer $A"
curl -s -o /dev/null -w "usage from > to (expect 400) %{http_code}\n" "$B/api/devices/$DID/usage?from=$D0&to=$D2" -H "Authorization: Bearer $A"
curl -s -o /dev/null -w "usage range 91 days (expect 400) %{http_code}\n" "$B/api/devices/$DID/usage?from=$(dt -90)&to=$D0" -H "Authorization: Bearer $A"
curl -s -o /dev/null -w "usage range 90 days (expect 200) %{http_code}\n" "$B/api/devices/$DID/usage?from=$(dt -89)&to=$D0" -H "Authorization: Bearer $A"
curl -s -o /dev/null -w "other family reads usage (expect 404) %{http_code}\n" "$B/api/devices/$DID/usage" -H "Authorization: Bearer $A2"
curl -s -o /dev/null -w "other family unknown device (expect 404) %{http_code}\n" "$B/api/devices/999999/usage" -H "Authorization: Bearer $A"
curl -s -o /dev/null -w "usage get with device token (expect 403) %{http_code}\n" "$B/api/devices/$DID/usage" -H "Authorization: Bearer $DT"
curl -s -o /dev/null -w "usage post with parent token (expect 403) %{http_code}\n" -X POST $B/api/devices/me/usage -H "$J" -H "Authorization: Bearer $A" -d '{"days":[]}'
curl -s -o /dev/null -w "usage post no token (expect 401) %{http_code}\n" -X POST $B/api/devices/me/usage -H "$J" -d '{"days":[]}'
curl -s -o /dev/null -w "usage get no token (expect 401) %{http_code}\n" "$B/api/devices/$DID/usage"
echo "other child same date is a separate row; next line expect child1 D0 still 1:"
up2() { curl -s -o /dev/null -w "$1 (expect $2) %{http_code}\n" -X POST $B/api/devices/me/usage -H "$J" -H "Authorization: Bearer $DT2" -d "$3"; }
up2 "child2 posts same date (own row, no clash)" 204 "{\"days\":[{\"date\":\"$D0\",\"totalMinutes\":7,\"blocks\":0,\"apps\":{\"com.a.b\":7}}]}"
curl -s "$B/api/devices/$DID/usage?from=$D0&to=$D0" -H "Authorization: Bearer $A" | python -c "import sys,json;d=json.load(sys.stdin)[0];print('child1 D0 still',d['totalMinutes'])"
# --- Cảnh báo cho mẹ (API-10): loại cho phép, detail chỉ là mã/số, chống trùng, giới hạn, đã đọc, cô lập gia đình ---
ts() { python -c "import datetime as d,sys;print((d.datetime.utcnow()+d.timedelta(minutes=float(sys.argv[1]))).strftime('%Y-%m-%dT%H:%M:%SZ'))" "$1"; }
al() { curl -s -o /dev/null -w "$2 (expect $3) %{http_code}\n" -X POST $B/api/devices/me/alerts -H "$J" -H "Authorization: Bearer $DT" -d "$1"; }
echo "mother lists alerts before any (expect []):"; curl -s "$B/api/devices/$DID/alerts" -H "Authorization: Bearer $A"; echo
al '{"kind":"accessibility_off"}' "alert accessibility_off" 200
curl -s -w "\nalert duplicate within window (expect 409 with id) %{http_code}\n" -X POST $B/api/devices/me/alerts -H "$J" -H "Authorization: Bearer $DT" -d '{"kind":"accessibility_off","detail":"settings_guard"}'
al "{\"kind\":\"time_changed\",\"detail\":\"-120\",\"occurredAt\":\"$(ts -60)\"}" "alert time_changed 1h ago, detail -120" 200
al "{\"kind\":\"time_changed\",\"detail\":\"30\",\"occurredAt\":\"$(ts -3)\"}" "alert time_changed 3 min ago (60 min apart from the previous: not duplicate)" 200
al '{"kind":"device_admin_off","detail":null}' "alert device_admin_off null detail" 200
al '{"kind":"permission_missing","detail":"usage_access"}' "alert permission_missing usage_access" 200
al '{"kind":"app_uninstall_attempt","detail":"authorized"}' "alert app_uninstall_attempt authorized" 200
al '{"kind":"khong_co"}' "alert unknown kind" 400
al '{"kind":""}' "alert empty kind" 400
al '{}' "alert missing kind" 400
al '{"kind":123}' "alert kind wrong type" 400
al "{\"kind\":\"$(python -c "print('a'*31)")\"}" "alert kind 31 chars" 400
al '{"kind":"offline"}' "alert child cannot send offline" 400
al '{"kind":"permission_missing","detail":"Co Dau"}' "alert detail with space/uppercase" 400
al '{"kind":"permission_missing","detail":"ten app: Zalo"}' "alert detail free text" 400
al '{"kind":"permission_missing","detail":"com.zing.zalo"}' "alert detail looks like package (dot)" 400
al "{\"kind\":\"permission_missing\",\"detail\":\"$(python -c "print('a'*33)")\"}" "alert detail 33 chars" 400
al '{"kind":"permission_missing","detail":5}' "alert detail wrong type (number)" 400
al "{\"kind\":\"permission_missing\",\"detail\":\"x\",\"occurredAt\":\"$(ts 60)\"}" "alert occurredAt 1h in future" 400
al "{\"kind\":\"permission_missing\",\"detail\":\"x\",\"occurredAt\":\"$(ts -11520)\"}" "alert occurredAt 8 days old" 400
al '{"kind":"permission_missing","detail":"x","occurredAt":"abc"}' "alert occurredAt not a date" 400
curl -s -o /dev/null -w "alert post with parent token (expect 403) %{http_code}\n" -X POST $B/api/devices/me/alerts -H "$J" -H "Authorization: Bearer $A" -d '{"kind":"accessibility_off"}'
curl -s -o /dev/null -w "alert post no token (expect 401) %{http_code}\n" -X POST $B/api/devices/me/alerts -H "$J" -d '{"kind":"accessibility_off"}'
echo "mother lists alerts (expect 5 rows ascending: accessibility_off, time_changed -120, time_changed 30, device_admin_off, permission_missing, app_uninstall_attempt = 6):"
curl -s "$B/api/devices/$DID/alerts" -H "Authorization: Bearer $A" | python -c "import sys,json;d=json.load(sys.stdin);print(len(d),[(x['kind'],x['detail'],x['readAt']) for x in d])"
AIDS=$(curl -s "$B/api/devices/$DID/alerts" -H "Authorization: Bearer $A" | python -c "import sys,json;print(' '.join(str(x['id']) for x in json.load(sys.stdin)))"); set -- $AIDS; AL1=$1; AL3=$3; ALLAST=${6}
echo "afterId=$AL3 (expect 3 rows after it):"; curl -s "$B/api/devices/$DID/alerts?afterId=$AL3" -H "Authorization: Bearer $A" | python -c "import sys,json;print(len(json.load(sys.stdin)))"
curl -s -o /dev/null -w "alerts afterId not a number (expect 400) %{http_code}\n" "$B/api/devices/$DID/alerts?afterId=abc" -H "Authorization: Bearer $A"
curl -s -o /dev/null -w "alerts list with device token (expect 403) %{http_code}\n" "$B/api/devices/$DID/alerts" -H "Authorization: Bearer $DT"
curl -s -o /dev/null -w "alerts list no token (expect 401) %{http_code}\n" "$B/api/devices/$DID/alerts"
curl -s -o /dev/null -w "other family lists alerts (expect 404) %{http_code}\n" "$B/api/devices/$DID/alerts" -H "Authorization: Bearer $A2"
curl -s -o /dev/null -w "unknown device alerts (expect 404) %{http_code}\n" "$B/api/devices/999999/alerts" -H "Authorization: Bearer $A"
curl -s -o /dev/null -w "other family marks read (expect 404) %{http_code}\n" -X POST $B/api/alerts/$AL1/read -H "Authorization: Bearer $A2"
curl -s -o /dev/null -w "mark read unknown alert (expect 404) %{http_code}\n" -X POST $B/api/alerts/999999/read -H "Authorization: Bearer $A"
curl -s -o /dev/null -w "mark read with device token (expect 403) %{http_code}\n" -X POST $B/api/alerts/$AL1/read -H "Authorization: Bearer $DT"
curl -s -o /dev/null -w "mark read no token (expect 401) %{http_code}\n" -X POST $B/api/alerts/$AL1/read
curl -s -o /dev/null -w "mark read ok (expect 200) %{http_code}\n" -X POST $B/api/alerts/$AL1/read -H "Authorization: Bearer $A"
R1=$(curl -s "$B/api/devices/$DID/alerts" -H "Authorization: Bearer $A" | python -c "import sys,json;print([x['readAt'] for x in json.load(sys.stdin) if x['id']==$AL1][0])")
curl -s -o /dev/null -w "mark read again (expect 200) %{http_code}\n" -X POST $B/api/alerts/$AL1/read -H "Authorization: Bearer $A"
R2=$(curl -s "$B/api/devices/$DID/alerts" -H "Authorization: Bearer $A" | python -c "import sys,json;print([x['readAt'] for x in json.load(sys.stdin) if x['id']==$AL1][0])")
echo "readAt set and unchanged by second call (expect True True): $([ "$R1" != "None" ] && echo True) $([ "$R1" = "$R2" ] && echo True)"
echo "other child may send the same kind (expect 200, separate device):"
curl -s -o /dev/null -w "other child accessibility_off %{http_code}\n" -X POST $B/api/devices/me/alerts -H "$J" -H "Authorization: Bearer $DT2" -d '{"kind":"accessibility_off"}'
echo "per-device cap: 205 distinct time_changed events on child 2 (expect rows kept = 200, newest kept):"
DID2=$(curl -s $B/api/devices -H "Authorization: Bearer $A2" | py "[0]['id']")
for i in $(seq 0 204); do python -c "import datetime as d,sys;print((d.datetime.utcnow()-d.timedelta(minutes=11*int(sys.argv[1])+1)).strftime('%Y-%m-%dT%H:%M:%SZ'))" $i; done | tr -d '\r' > /tmp/sf_alert_times.txt
CAPFAIL=0; while read T; do C=$(curl -s -o /dev/null -w "%{http_code}" -X POST $B/api/devices/me/alerts -H "$J" -H "Authorization: Bearer $DT2" -d "{\"kind\":\"time_changed\",\"detail\":\"5\",\"occurredAt\":\"$T\"}"); [ "$C" = "200" ] || { CAPFAIL=$((CAPFAIL+1)); echo "  unexpected $C for $T"; }; done < /tmp/sf_alert_times.txt
echo "cap posts not 200: $CAPFAIL (expect 0)"
TOTAL=0; AFTER=1; while :; do PAGE=$(curl -s "$B/api/devices/$DID2/alerts?afterId=$AFTER" -H "Authorization: Bearer $A2" | python -c "import sys,json;d=json.load(sys.stdin);print(len(d),d[-1]['id'] if d else 0)"); set -- $PAGE; [ "$1" = "0" ] && break; TOTAL=$((TOTAL+$1)); AFTER=$2; done
echo "child 2 total alert rows (expect 200): $TOTAL"
if [ -n "$SF_SQL_SERVER" ] && [ -n "$SF_SQL_DB" ] && command -v sqlcmd >/dev/null; then
  sq() { sqlcmd -S "$SF_SQL_SERVER" -d "$SF_SQL_DB" -E -h -1 -W -Q "SET NOCOUNT ON; $1" | tr -d '\r' | head -1; }
  echo "SQL: retention - insert a 40-day-old alert, then child sends a new event; the old row must be purged"
  sq "INSERT INTO Alerts(DeviceId,Kind,Detail,CreatedAt) VALUES ($DID,'permission_missing','old',DATEADD(day,-40,SYSUTCDATETIME()))" >/dev/null
  echo "  old rows before (expect 1): $(sq "SELECT COUNT(*) FROM Alerts WHERE DeviceId=$DID AND Detail='old'")"
  al "{\"kind\":\"time_changed\",\"detail\":\"7\",\"occurredAt\":\"$(ts -180)\"}" "  new event (3h ago)" 200
  echo "  old rows after (expect 0): $(sq "SELECT COUNT(*) FROM Alerts WHERE DeviceId=$DID AND Detail='old'")"
  echo "SQL: offline detection needs the API started with Alerts__CheckIntervalSeconds=3 (threshold stays 24h by default)"
  sq "UPDATE Devices SET LastSeenAt=DATEADD(hour,-25,SYSUTCDATETIME()) WHERE Id=$DID" >/dev/null
  sleep 8
  echo "  offline alerts after 25h silence (expect 1): $(sq "SELECT COUNT(*) FROM Alerts WHERE DeviceId=$DID AND Kind='offline'")  detail (expect 25): $(sq "SELECT Detail FROM Alerts WHERE DeviceId=$DID AND Kind='offline'")"
  sleep 8
  echo "  offline alerts after several more checks (expect still 1, no repeat): $(sq "SELECT COUNT(*) FROM Alerts WHERE DeviceId=$DID AND Kind='offline'")"
  echo "mother sees the offline alert (expect offline|25|None):"; curl -s "$B/api/devices/$DID/alerts?afterId=$ALLAST" -H "Authorization: Bearer $A" | python -c "import sys,json;print([(x['kind'],x['detail'],x['readAt']) for x in json.load(sys.stdin) if x['kind']=='offline'])"
  curl -s -o /dev/null -w "child comes back online (any call, expect 200) %{http_code}\n" $B/api/devices/me/policy -H "Authorization: Bearer $DT"
  sleep 8
  echo "  still 1 offline alert once back online (expect 1): $(sq "SELECT COUNT(*) FROM Alerts WHERE DeviceId=$DID AND Kind='offline'")"
  # Mô phỏng: cảnh báo cũ xảy ra 60 giờ trước, máy online lại lúc 30 giờ trước rồi im lặng tiếp (sau lần online mà chưa có cảnh báo).
  sq "UPDATE Alerts SET CreatedAt=DATEADD(hour,-60,SYSUTCDATETIME()) WHERE DeviceId=$DID AND Kind='offline'" >/dev/null
  sq "UPDATE Devices SET LastSeenAt=DATEADD(hour,-30,SYSUTCDATETIME()) WHERE Id=$DID" >/dev/null
  sleep 8
  echo "  second silence = new episode (expect 2): $(sq "SELECT COUNT(*) FROM Alerts WHERE DeviceId=$DID AND Kind='offline'")"
  sq "UPDATE Devices SET LastSeenAt=SYSUTCDATETIME() WHERE Id=$DID" >/dev/null
else
  echo "SKIP: retention + offline detection need SF_SQL_SERVER / SF_SQL_DB and sqlcmd (see docs/API_TIEN_TRINH.md)"
fi
R3=$(curl -s -X POST $B/api/devices/me/requests -H "$J" -H "Authorization: Bearer $DT" -d '{"kind":"study_done"}'); RID3=$(echo $R3 | py "['id']")
# --- Đổi tên máy, xem thông tin máy mình (API-01) ---
code "rename ok" 200 -X PATCH $B/api/devices/$DID -H "$J" -H "Authorization: Bearer $A" -d '{"name":"  Be Bin  "}'
echo "list shows trimmed name (expect Be Bin): $(curl -s $B/api/devices -H "Authorization: Bearer $A" | py "[0]['name']")"
echo "me name (expect Be Bin): $(curl -s $B/api/devices/me -H "Authorization: Bearer $DT" | py "['name']")"
echo "me family (expect Gia đình): $(curl -s $B/api/devices/me -H "Authorization: Bearer $DT" | py "['familyName']")"
echo "me has no email (expect 0): $(curl -s $B/api/devices/me -H "Authorization: Bearer $DT" | grep -c '@')"
code "rename empty" 400 -X PATCH $B/api/devices/$DID -H "$J" -H "Authorization: Bearer $A" -d '{"name":"   "}'
code "rename missing field" 400 -X PATCH $B/api/devices/$DID -H "$J" -H "Authorization: Bearer $A" -d '{}'
code "rename wrong type" 400 -X PATCH $B/api/devices/$DID -H "$J" -H "Authorization: Bearer $A" -d '{"name":5}'
code "rename too long" 400 -X PATCH $B/api/devices/$DID -H "$J" -H "Authorization: Bearer $A" -d "{\"name\":\"$(printf 'a%.0s' $(seq 1 51))\"}"
code "rename control char" 400 -X PATCH $B/api/devices/$DID -H "$J" -H "Authorization: Bearer $A" -d '{"name":"a
b"}'
echo "name unchanged after bad renames (expect Be Bin): $(curl -s $B/api/devices -H "Authorization: Bearer $A" | py "[0]['name']")"
code "rename other family" 404 -X PATCH $B/api/devices/$DID -H "$J" -H "Authorization: Bearer $EB" -d '{"name":"X"}'
code "rename by device token" 403 -X PATCH $B/api/devices/$DID -H "$J" -H "Authorization: Bearer $DT" -d '{"name":"X"}'
code "me by parent token" 403 $B/api/devices/me -H "Authorization: Bearer $A"
code "me no token" 401 $B/api/devices/me
curl -s -o /dev/null -w "unpair (expect 204) %{http_code}\n" -X DELETE $B/api/devices/$DID -H "Authorization: Bearer $A"
dec $RID3 '{"decision":"approved"}' "approve after unpair" 404
curl -s -o /dev/null -w "list after unpair (expect 404) %{http_code}\n" "$B/api/devices/$DID/requests" -H "Authorization: Bearer $A"
curl -s -o /dev/null -w "child request after unpair (expect 401) %{http_code}\n" -X POST $B/api/devices/me/requests -H "$J" -H "Authorization: Bearer $DT" -d '{"kind":"study_done"}'
curl -s -o /dev/null -w "usage get after unpair (expect 404) %{http_code}\n" "$B/api/devices/$DID/usage" -H "Authorization: Bearer $A"
code "sharing get after unpair" 404 $B/api/devices/$DID/location-sharing -H "Authorization: Bearer $A"
code "sharing put after unpair" 404 -X PUT $B/api/devices/$DID/location-sharing -H "$J" -H "Authorization: Bearer $A" -d '{"enabled":false}'
code "delete locations after unpair" 404 -X DELETE $B/api/devices/$DID/locations -H "Authorization: Bearer $A"
code "settings after unpair" 401 $B/api/devices/me/settings -H "Authorization: Bearer $DT"
curl -s -o /dev/null -w "usage post after unpair (expect 401) %{http_code}\n" -X POST $B/api/devices/me/usage -H "$J" -H "Authorization: Bearer $DT" -d '{"days":[]}'
if [ -n "$SF_SQL_SERVER" ] && [ -n "$SF_SQL_DB" ] && command -v sqlcmd >/dev/null; then
  sq "UPDATE Devices SET LastSeenAt=DATEADD(hour,-50,SYSUTCDATETIME()) WHERE Id=$DID" >/dev/null
  sleep 8
  echo "revoked device never gets an offline alert (expect still 2): $(sq "SELECT COUNT(*) FROM Alerts WHERE DeviceId=$DID AND Kind='offline'")"
fi
code "rename after unpair" 404 -X PATCH $B/api/devices/$DID -H "$J" -H "Authorization: Bearer $A" -d '{"name":"X"}'
code "me after unpair" 401 $B/api/devices/me -H "Authorization: Bearer $DT"
# --- Kiểm thử chéo gia đình / token / mã ghép (API-15): thế giới mới, không dùng lại $DID đã hủy ghép ---
# Chạy smoke nên đặt RateLimit__AuthPerMinute và RateLimit__ClaimPer10Min lớn khi khởi động API (xem docs/API_TIEN_TRINH.md); không đặt thì
# khởi động lại API giữa các lần chạy và phần ghép đôi bị 429 khi smoke có hơn 5 lần claim.
reg() { curl -s -X POST $B/api/auth/register -H "$J" -d "{\"email\":\"$1$RANDOM@x.com\",\"password\":\"password123\"}"; }
R1=$(reg p); M1=$(echo "$R1" | py "['accessToken']"); RT1=$(echo "$R1" | py "['refreshToken']")
M2=$(reg q | py "['accessToken']")
CODE15=$(curl -s -X POST $B/api/pairing/code -H "$J" -H "Authorization: Bearer $M1" -d '{"deviceName":"Con 15"}' | py "['code']")
CL15=$(curl -s -X POST $B/api/pairing/claim -H "$J" -d "{\"code\":\"$CODE15\"}")
K15=$(echo "$CL15" | py "['deviceToken']"); D15=$(echo "$CL15" | py "['deviceId']")
code "pairing code reused" 400 -X POST $B/api/pairing/claim -H "$J" -d "{\"code\":\"$CODE15\"}"
code "pairing code wrong length" 400 -X POST $B/api/pairing/claim -H "$J" -d '{"code":"12345"}'
code "pairing code missing" 400 -X POST $B/api/pairing/claim -H "$J" -d '{}'
code "pairing code by device token" 403 -X POST $B/api/pairing/code -H "$J" -H "Authorization: Bearer $K15" -d '{}'
NOW15=$(date -u +%FT%TZ)
curl -s -o /dev/null -X POST $B/api/devices/me/apps -H "$J" -H "Authorization: Bearer $K15" -d '{"apps":[{"packageName":"com.seed.app","label":"Seed","isNew":true}]}'
RQ15=$(curl -s -X POST $B/api/devices/me/requests -H "$J" -H "Authorization: Bearer $K15" -d '{"kind":"extra_time","payloadJson":"{\"minutes\":10}"}' | py "['id']")
AL15=$(curl -s -X POST $B/api/devices/me/alerts -H "$J" -H "Authorization: Bearer $K15" -d '{"kind":"time_changed"}' | py "['id']")
# Mỗi dòng: tên|phương thức|đường dẫn|body. Mẹ B (M2) phải 404; mẹ A (M1) phải 2xx (đối chứng đường dẫn đúng).
while IFS='|' read -r NM MT PT BD; do
  PT=${PT//\{id\}/$D15}; PT=${PT//\{req\}/$RQ15}; PT=${PT//\{alert\}/$AL15}
  if [ -n "$BD" ]; then ARGS=(-d "$BD"); else ARGS=(); fi
  code "x-family $NM (other mother)" 404 -X $MT "$B$PT" -H "$J" -H "Authorization: Bearer $M2" "${ARGS[@]}"
  code "x-family $NM (owner, expect 2xx)" "2xx" -X $MT "$B$PT" -H "$J" -H "Authorization: Bearer $M1" "${ARGS[@]}"
  code "x-family $NM (device token)" 403 -X $MT "$B$PT" -H "$J" -H "Authorization: Bearer $K15" "${ARGS[@]}"
  code "x-family $NM (no token)" 401 -X $MT "$B$PT" -H "$J" "${ARGS[@]}"
done <<'EOF'
rename|PATCH|/api/devices/{id}|{"name":"Ten moi"}
policy get|GET|/api/devices/{id}/policy|
policy put|PUT|/api/devices/{id}/policy|{"json":"{}","expectedVersion":0}
apps list|GET|/api/devices/{id}/apps|
app decide|PUT|/api/devices/{id}/apps/com.seed.app|{"status":"blocked"}
command post|POST|/api/devices/{id}/commands|{"type":"pause","payloadJson":"{\"minutes\":5}"}
commands list|GET|/api/devices/{id}/commands|
status|GET|/api/devices/{id}/status|
requests list|GET|/api/devices/{id}/requests|
usage|GET|/api/devices/{id}/usage|
alerts list|GET|/api/devices/{id}/alerts|
sharing get|GET|/api/devices/{id}/location-sharing|
sharing put|PUT|/api/devices/{id}/location-sharing|{"enabled":true}
locations delete|DELETE|/api/devices/{id}/locations|
location last|GET|/api/devices/{id}/location|
locations history|GET|/api/devices/{id}/locations|
geofences get|GET|/api/devices/{id}/geofences|
geofences put|PUT|/api/devices/{id}/geofences|{"geofences":[],"expectedVersion":0}
geofence events|GET|/api/devices/{id}/geofence-events|
request decide|PUT|/api/requests/{req}|{"decision":"rejected"}
alert read|POST|/api/alerts/{alert}/read|
EOF
code "unpair by other mother" 404 -X DELETE $B/api/devices/$D15 -H "Authorization: Bearer $M2"
echo "device still listed for owner (expect 1): $(curl -s $B/api/devices -H "Authorization: Bearer $M1" | python -c "import sys,json;print(len(json.load(sys.stdin)))")"
echo "device list of other mother (expect 0): $(curl -s $B/api/devices -H "Authorization: Bearer $M2" | python -c "import sys,json;print(len(json.load(sys.stdin)))")"
# Token giả / sai vai trò
code "forged token parent route" 401 $B/api/devices -H "Authorization: Bearer abc.def.ghi"
code "garbage token device route" 401 $B/api/devices/me -H "Authorization: Bearer khong-phai-jwt"
code "parent token on device route" 403 $B/api/devices/me/policy -H "Authorization: Bearer $M1"
# Refresh token: dùng lại token đã đổi phải 401
RF2=$(curl -s -X POST $B/api/auth/refresh -H "$J" -d "{\"refreshToken\":\"$RT1\"}" | py "['refreshToken']")
code "refresh old token reused" 401 -X POST $B/api/auth/refresh -H "$J" -d "{\"refreshToken\":\"$RT1\"}"
code "refresh new token" 200 -X POST $B/api/auth/refresh -H "$J" -d "{\"refreshToken\":\"$RF2\"}"
code "refresh garbage" 401 -X POST $B/api/auth/refresh -H "$J" -d '{"refreshToken":"khong-co"}'
code "refresh missing" 400 -X POST $B/api/auth/refresh -H "$J" -d '{}'
# Hủy ghép: mọi endpoint phía con phải 401
code "unpair (owner)" 204 -X DELETE $B/api/devices/$D15 -H "Authorization: Bearer $M1"
code "unpair again" 404 -X DELETE $B/api/devices/$D15 -H "Authorization: Bearer $M1"
for P in "" /settings /policy /commands /apps/decisions /geofences /requests/1; do
  code "revoked device GET /me$P" 401 $B/api/devices/me$P -H "Authorization: Bearer $K15"
done
code "revoked device PUT status" 401 -X PUT $B/api/devices/me/status -H "$J" -H "Authorization: Bearer $K15" -d '{"policyVersion":0,"isPaused":false,"studyActive":false}'
code "revoked device POST alerts" 401 -X POST $B/api/devices/me/alerts -H "$J" -H "Authorization: Bearer $K15" -d '{"kind":"time_changed"}'
code "revoked device POST locations" 401 -X POST $B/api/devices/me/locations -H "$J" -H "Authorization: Bearer $K15" -d "{\"points\":[{\"lat\":1,\"lng\":1,\"accuracy\":1,\"time\":\"$NOW15\"}]}"
code "revoked device POST ack" 401 -X POST $B/api/devices/me/commands/1/ack -H "Authorization: Bearer $K15"
# Swagger: mọi endpoint phải hiện (test tích hợp SafeFamily.Api.Tests so khớp từng action; ở đây chỉ in số đường dẫn)
echo "swagger path count (info): $(curl -s $B/swagger/v1/swagger.json | py "['paths'].__len__()")"
# --- Hoàn thiện tài khoản (API-03): đăng xuất, đổi mật khẩu, quên/đặt lại mật khẩu, xóa tài khoản ---
# Cần chạy API với RateLimit__AuthPerMinute=1000 (smoke gọi /api/auth nhiều hơn 10 lần/phút) và RateLimit__ClaimPer10Min=1000
# (smoke ghép đôi quá 5 lần/10 phút; không thì bước ghép máy thất bại với 429). Phần quên mật khẩu cần
# Smtp__PickupDirectory=<thư mục> + Smtp__From=a@b.c khi chạy API và SF_MAIL_DIR=<cùng thư mục> khi chạy smoke.
PW=password123; PW2=matkhaumoi456
EA="acc$RANDOM@x.com"
authj() { curl -s -X POST $B/api/auth/$1 -H "$J" -d "$2"; }
S1=$(authj register "{\"email\":\"$EA\",\"password\":\"$PW\"}"); AA=$(echo $S1 | py "['accessToken']"); RT1=$(echo $S1 | py "['refreshToken']")
S2=$(authj login "{\"email\":\"$EA\",\"password\":\"$PW\"}"); AA2=$(echo $S2 | py "['accessToken']"); RT2=$(echo $S2 | py "['refreshToken']")
S3=$(authj login "{\"email\":\"$EA\",\"password\":\"$PW\"}"); RT3=$(echo $S3 | py "['refreshToken']")
rf() { curl -s -o /dev/null -w "%{http_code}" -X POST $B/api/auth/refresh -H "$J" -d "{\"refreshToken\":\"$1\"}"; }
# Logout
code "logout missing body field" 400 -X POST $B/api/auth/logout -H "$J" -d '{}'
code "logout wrong type" 400 -X POST $B/api/auth/logout -H "$J" -d '{"refreshToken":5}'
code "logout token 201 chars" 400 -X POST $B/api/auth/logout -H "$J" -d "{\"refreshToken\":\"$(python -c "print('a'*201)")\"}"
code "logout unknown token (idempotent)" 204 -X POST $B/api/auth/logout -H "$J" -d '{"refreshToken":"khong-co-token-nay"}'
code "logout session 1" 204 -X POST $B/api/auth/logout -H "$J" -d "{\"refreshToken\":\"$RT1\"}"
echo "refresh with logged-out token (expect 401): $(rf $RT1)"
code "logout session 1 again" 204 -X POST $B/api/auth/logout -H "$J" -d "{\"refreshToken\":\"$RT1\"}"
echo "other sessions untouched by logout, S3 refresh (expect 200): $(rf $RT3)"
RT3=$(authj login "{\"email\":\"$EA\",\"password\":\"$PW\"}" | py "['refreshToken']")
# Đổi mật khẩu
cpw() { curl -s -o /dev/null -w "$1 (expect $2) %{http_code}\n" -X POST $B/api/auth/change-password -H "$J" ${5:+-H "Authorization: Bearer $5"} -d "$3"; }
cpw "change-pw no token" 401 "{\"currentPassword\":\"$PW\",\"newPassword\":\"$PW2\"}"
cpw "change-pw device token" 403 "{\"currentPassword\":\"$PW\",\"newPassword\":\"$PW2\"}" "" "$DT"
cpw "change-pw missing fields" 400 '{}' "" "$AA2"
cpw "change-pw wrong type" 400 '{"currentPassword":5,"newPassword":6}' "" "$AA2"
cpw "change-pw new too short" 400 "{\"currentPassword\":\"$PW\",\"newPassword\":\"abc\"}" "" "$AA2"
cpw "change-pw new 129 chars" 400 "{\"currentPassword\":\"$PW\",\"newPassword\":\"$(python -c "print('a'*129)")\"}" "" "$AA2"
cpw "change-pw refreshToken wrong type" 400 "{\"currentPassword\":\"$PW\",\"newPassword\":\"$PW2\",\"refreshToken\":5}" "" "$AA2"
cpw "change-pw wrong current password" 403 "{\"currentPassword\":\"sai-roi-nhe\",\"newPassword\":\"$PW2\"}" "" "$AA2"
cpw "change-pw new equals old" 400 "{\"currentPassword\":\"$PW\",\"newPassword\":\"$PW\"}" "" "$AA2"
code "old password still works after bad attempts" 200 -X POST $B/api/auth/login -H "$J" -d "{\"email\":\"$EA\",\"password\":\"$PW\"}"
echo "S2 and S3 still valid before change (expect 200 200): $(rf $RT2) $(rf $RT3)"
S2=$(authj login "{\"email\":\"$EA\",\"password\":\"$PW\"}"); AA2=$(echo $S2 | py "['accessToken']"); RT2=$(echo $S2 | py "['refreshToken']")
S3=$(authj login "{\"email\":\"$EA\",\"password\":\"$PW\"}"); RT3=$(echo $S3 | py "['refreshToken']")
cpw "change-pw ok (keeps session 2)" 204 "{\"currentPassword\":\"$PW\",\"newPassword\":\"$PW2\",\"refreshToken\":\"$RT2\"}" "" "$AA2"
code "login old password" 401 -X POST $B/api/auth/login -H "$J" -d "{\"email\":\"$EA\",\"password\":\"$PW\"}"
code "login new password" 200 -X POST $B/api/auth/login -H "$J" -d "{\"email\":\"$EA\",\"password\":\"$PW2\"}"
echo "after change: other session refresh (expect 401): $(rf $RT3)   current session refresh (expect 200): $(rf $RT2)"
# Quên / đặt lại mật khẩu
fp() { curl -s -o /dev/null -w "$1 (expect $2) %{http_code}\n" -X POST $B/api/auth/forgot-password -H "$J" -d "$3"; }
rp() { curl -s -o /dev/null -w "$1 (expect $2) %{http_code}\n" -X POST $B/api/auth/reset-password -H "$J" -d "$3"; }
fp "forgot unknown email (no leak)" 204 '{"email":"khong.ton.tai@x.com"}'
fp "forgot not an email" 400 '{"email":"abc"}'
fp "forgot missing email" 400 '{}'
fp "forgot email wrong type" 400 '{"email":5}'
rp "reset code too short" 400 "{\"email\":\"$EA\",\"code\":\"12345\",\"newPassword\":\"$PW\"}"
rp "reset code letters" 400 "{\"email\":\"$EA\",\"code\":\"abcdef\",\"newPassword\":\"$PW\"}"
rp "reset code number type" 400 "{\"email\":\"$EA\",\"code\":123456,\"newPassword\":\"$PW\"}"
rp "reset new password too short" 400 "{\"email\":\"$EA\",\"code\":\"123456\",\"newPassword\":\"abc\"}"
rp "reset missing fields" 400 '{}'
rp "reset unknown email" 400 "{\"email\":\"khong.ton.tai@x.com\",\"code\":\"123456\",\"newPassword\":\"$PW\"}"
rp "reset without a pending code" 400 "{\"email\":\"$EA\",\"code\":\"123456\",\"newPassword\":\"$PW\"}"
mailcode() { # $1 = email người nhận: in ra mã 6 số trong thư mới nhất gửi tới email đó
  python -c "
import sys,glob,os,email
want=sys.argv[2].lower(); best=None
for f in sorted(glob.glob(os.path.join(sys.argv[1],'*.eml')),key=os.path.getmtime,reverse=True):
    m=email.message_from_binary_file(open(f,'rb'))
    if want in (m['To'] or '').lower():
        import re
        body=m.get_payload(decode=True).decode('utf-8','replace')
        r=re.search(r'\b(\d{6})\b',body)
        if r: best=r.group(1); break
print(best or '')
" "$SF_MAIL_DIR" "$1"; }
wrongcode() { python -c "import sys;print('%06d'%((int(sys.argv[1])+1)%1000000))" "$1"; }
if [ -n "$SF_MAIL_DIR" ]; then
  fp "forgot known email" 204 "{\"email\":\"$EA\"}"
  sleep 2
  RC=$(mailcode "$EA")
  echo "mail has a 6-digit code (expect 6): ${#RC}"
  fp "forgot again within 60s (ignored, same code stays valid)" 204 "{\"email\":\"$EA\"}"
  sleep 1
  echo "mail files for this account (expect 1): $(grep -l -i "$EA" "$SF_MAIL_DIR"/*.eml 2>/dev/null | wc -l)"
  rp "reset wrong code" 400 "{\"email\":\"$EA\",\"code\":\"$(wrongcode $RC)\",\"newPassword\":\"$PW\"}"
  code "password unchanged after wrong code" 200 -X POST $B/api/auth/login -H "$J" -d "{\"email\":\"$EA\",\"password\":\"$PW2\"}"
  rp "reset right code, new password too short" 400 "{\"email\":\"$EA\",\"code\":\"$RC\",\"newPassword\":\"abc\"}"
  rp "reset right code" 204 "{\"email\":\"$EA\",\"code\":\"$RC\",\"newPassword\":\"$PW\"}"
  rp "reset same code again (used)" 400 "{\"email\":\"$EA\",\"code\":\"$RC\",\"newPassword\":\"$PW\"}"
  code "login after reset (old password restored)" 200 -X POST $B/api/auth/login -H "$J" -d "{\"email\":\"$EA\",\"password\":\"$PW\"}"
  code "login with password before reset" 401 -X POST $B/api/auth/login -H "$J" -d "{\"email\":\"$EA\",\"password\":\"$PW2\"}"
  echo "reset revoked old sessions, S2 refresh (expect 401): $(rf $RT2)"
  # Nhập sai 5 lần thì mã bị hủy, kể cả khi sau đó nhập đúng
  EL="lock$RANDOM@x.com"; authj register "{\"email\":\"$EL\",\"password\":\"$PW\"}" >/dev/null
  fp "forgot (lockout account)" 204 "{\"email\":\"$EL\"}"; sleep 2
  RL=$(mailcode "$EL"); WL=$(wrongcode $RL)
  for i in 1 2 3 4 5; do rp "  wrong attempt $i" 400 "{\"email\":\"$EL\",\"code\":\"$WL\",\"newPassword\":\"$PW2\"}"; done
  rp "right code after 5 wrong attempts (locked)" 400 "{\"email\":\"$EL\",\"code\":\"$RL\",\"newPassword\":\"$PW2\"}"
  code "password unchanged after lockout" 200 -X POST $B/api/auth/login -H "$J" -d "{\"email\":\"$EL\",\"password\":\"$PW\"}"
  if [ -n "$SF_SQL_SERVER" ] && [ -n "$SF_SQL_DB" ] && command -v sqlcmd >/dev/null; then
    EX="exp$RANDOM@x.com"; authj register "{\"email\":\"$EX\",\"password\":\"$PW\"}" >/dev/null
    fp "forgot (expiry account)" 204 "{\"email\":\"$EX\"}"; sleep 2
    RX=$(mailcode "$EX")
    sqlcmd -S "$SF_SQL_SERVER" -d "$SF_SQL_DB" -E -Q "UPDATE PasswordResets SET ExpiresAt=DATEADD(minute,-1,SYSUTCDATETIME()) WHERE ParentId=(SELECT Id FROM Parents WHERE Email='$EX')" >/dev/null
    rp "reset with expired code" 400 "{\"email\":\"$EX\",\"code\":\"$RX\",\"newPassword\":\"$PW2\"}"
  else
    echo "SKIP: expired reset code needs SF_SQL_SERVER / SF_SQL_DB and sqlcmd"
  fi
else
  echo "SKIP: forgot/reset with a real code needs SF_MAIL_DIR (API started with Smtp__PickupDirectory=<same dir> and Smtp__From)"
fi
# Xóa tài khoản: một gia đình có máy con và dữ liệu; gia đình khác không bị ảnh hưởng
EDEL="del$RANDOM@x.com"
SD=$(authj register "{\"email\":\"$EDEL\",\"password\":\"$PW\"}"); AD=$(echo $SD | py "['accessToken']"); RTD=$(echo $SD | py "['refreshToken']")
CODED=$(curl -s -X POST $B/api/pairing/code -H "$J" -H "Authorization: Bearer $AD" -d '{"deviceName":"Con xoa"}' | py "['code']")
CLD=$(curl -s -X POST $B/api/pairing/claim -H "$J" -d "{\"code\":\"$CODED\"}"); DTD=$(echo $CLD | py "['deviceToken']"); DIDD=$(echo $CLD | py "['deviceId']")
curl -s -o /dev/null -X POST $B/api/devices/me/locations -H "$J" -H "Authorization: Bearer $DTD" -d "{\"points\":[{\"lat\":10.77,\"lng\":106.7,\"accuracy\":12,\"time\":\"$NOW\"}]}"
curl -s -o /dev/null -X POST $B/api/devices/me/alerts -H "$J" -H "Authorization: Bearer $DTD" -d '{"kind":"accessibility_off"}'
curl -s -o /dev/null -X POST $B/api/devices/me/usage -H "$J" -H "Authorization: Bearer $DTD" -d "{\"days\":[{\"date\":\"$(dt 0)\",\"totalMinutes\":5,\"blocks\":0,\"apps\":{\"com.a.b\":5}}]}"
curl -s -o /dev/null -X PUT $B/api/devices/$DIDD/policy -H "$J" -H "Authorization: Bearer $AD" -d "$(pj '{"schemaVersion":1}' 0)"
curl -s -o /dev/null -X POST $B/api/pairing/code -H "$J" -H "Authorization: Bearer $AD" -d '{"deviceName":"Ma chua dung"}'
dl() { curl -s -o /dev/null -w "$1 (expect $2) %{http_code}\n" -X DELETE $B/api/auth/account -H "$J" ${5:+-H "Authorization: Bearer $5"} -d "$3"; }
dl "delete account no token" 401 "{\"password\":\"$PW\",\"confirm\":true}"
dl "delete account device token" 403 "{\"password\":\"$PW\",\"confirm\":true}" "" "$DTD"
dl "delete account empty body" 400 '{}' "" "$AD"
dl "delete account missing password" 400 '{"confirm":true}' "" "$AD"
dl "delete account missing confirm" 400 "{\"password\":\"$PW\"}" "" "$AD"
dl "delete account confirm false" 400 "{\"password\":\"$PW\",\"confirm\":false}" "" "$AD"
dl "delete account confirm string" 400 "{\"password\":\"$PW\",\"confirm\":\"yes\"}" "" "$AD"
dl "delete account password wrong type" 400 '{"password":5,"confirm":true}' "" "$AD"
dl "delete account wrong password" 403 '{"password":"sai-roi-nhe","confirm":true}' "" "$AD"
echo "family intact after bad attempts (expect 1 device, login 200): $(curl -s $B/api/devices -H "Authorization: Bearer $AD" | python -c "import sys,json;print(len(json.load(sys.stdin)))") $(curl -s -o /dev/null -w "%{http_code}" -X POST $B/api/auth/login -H "$J" -d "{\"email\":\"$EDEL\",\"password\":\"$PW\"}")"
dl "delete account ok" 204 "{\"password\":\"$PW\",\"confirm\":true}" "" "$AD"
code "login after delete" 401 -X POST $B/api/auth/login -H "$J" -d "{\"email\":\"$EDEL\",\"password\":\"$PW\"}"
echo "refresh after delete (expect 401): $(rf $RTD)"
code "child token after delete" 401 $B/api/devices/me/policy -H "Authorization: Bearer $DTD"
code "child post after delete" 401 -X POST $B/api/devices/me/alerts -H "$J" -H "Authorization: Bearer $DTD" -d '{"kind":"accessibility_off"}'
code "claim the leftover pairing code after delete" 400 -X POST $B/api/pairing/claim -H "$J" -d "{\"code\":\"$CODED\"}"
echo "old access token sees no devices (expect 0): $(curl -s $B/api/devices -H "Authorization: Bearer $AD" | python -c "import sys,json;print(len(json.load(sys.stdin)))")"
dl "delete account twice (parent gone)" 404 "{\"password\":\"$PW\",\"confirm\":true}" "" "$AD"
code "register the same email again" 200 -X POST $B/api/auth/register -H "$J" -d "{\"email\":\"$EDEL\",\"password\":\"$PW\"}"
echo "other family untouched (expect 1 device): $(curl -s $B/api/devices -H "Authorization: Bearer $A2" | python -c "import sys,json;print(len(json.load(sys.stdin)))")"
if [ -n "$SF_SQL_SERVER" ] && [ -n "$SF_SQL_DB" ] && command -v sqlcmd >/dev/null; then
  sq3() { sqlcmd -S "$SF_SQL_SERVER" -d "$SF_SQL_DB" -E -h -1 -W -Q "SET NOCOUNT ON; $1" | tr -d '\r' | head -1; }
  echo "SQL leftover rows of the deleted device (expect 0 for each): devices=$(sq3 "SELECT COUNT(*) FROM Devices WHERE Id=$DIDD") locations=$(sq3 "SELECT COUNT(*) FROM LocationPoints WHERE DeviceId=$DIDD") alerts=$(sq3 "SELECT COUNT(*) FROM Alerts WHERE DeviceId=$DIDD") usage=$(sq3 "SELECT COUNT(*) FROM UsageDays WHERE DeviceId=$DIDD") usageapps=$(sq3 "SELECT COUNT(*) FROM UsageApps WHERE UsageDayId NOT IN (SELECT Id FROM UsageDays)") policies=$(sq3 "SELECT COUNT(*) FROM Policies WHERE DeviceId=$DIDD") pairings=$(sq3 "SELECT COUNT(*) FROM Pairings WHERE Code='$CODED'") parents=$(sq3 "SELECT COUNT(*) FROM Parents WHERE Email='$EDEL'") (1 = the re-registered account)"
else
  echo "SKIP: leftover-row check needs SF_SQL_SERVER / SF_SQL_DB and sqlcmd"
fi
