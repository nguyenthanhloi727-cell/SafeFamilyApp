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
