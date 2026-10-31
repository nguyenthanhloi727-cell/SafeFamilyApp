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
R3=$(curl -s -X POST $B/api/devices/me/requests -H "$J" -H "Authorization: Bearer $DT" -d '{"kind":"study_done"}'); RID3=$(echo $R3 | py "['id']")
curl -s -o /dev/null -w "unpair (expect 204) %{http_code}\n" -X DELETE $B/api/devices/$DID -H "Authorization: Bearer $A"
dec $RID3 '{"decision":"approved"}' "approve after unpair" 404
curl -s -o /dev/null -w "list after unpair (expect 404) %{http_code}\n" "$B/api/devices/$DID/requests" -H "Authorization: Bearer $A"
curl -s -o /dev/null -w "child request after unpair (expect 401) %{http_code}\n" -X POST $B/api/devices/me/requests -H "$J" -H "Authorization: Bearer $DT" -d '{"kind":"study_done"}'
