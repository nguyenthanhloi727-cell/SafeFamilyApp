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
