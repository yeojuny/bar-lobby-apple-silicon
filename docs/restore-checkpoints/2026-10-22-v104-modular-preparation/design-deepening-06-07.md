# #6·#7 상세 설계 — 미적용 모듈 준비

두항목모두정확하게범위를좁히면지금source-only패치로작성할수있다. #6은성공feedback의예비notify 한곳만조건부로바꾸는작은수정이다. #7은첫성공검증의불변상대순서proof를submit-local로전달하는작은내부helper수정이며,current-event검사는전부남긴다. 이것은동시성/실GPU/시간절감을이미검증했다는판정이아니다. 두항목을서로의전제나전체#13대기제거로확대하지않는다. R/Small의Submission본문은공통이므로encoder reserve와독립인모듈로준비할수있지만부모전체핀은각각고정해야한다.

## 실제 객체·호출·소유권

| 대상 | 실제 위치/역할 | 유지할 계약 |
| --- | --- | --- |
| queue state | Submission.mm:735 부근 submitMutex/stateMutex/idle/pending/completed/firstError | feedback은submitMutex를잡지않음. idle predicate는stateMutex아래pending==0 또는firstError. |
| child state | :1187 mutex/done/phase/error/signals 등 | child wait predicate는childmutex아래Completed 또는error. |
| group | :1357 MVKMetal4SubmissionGroup | owner/children강한소유;child는group를역소유하지않음. work/tail/submitFinished/errorHandlers/GPUStorage/signalNotification의단일retirementgate. |
| error publication | :1457 publishGroupError | group→child잠금하에firsterror전파;handler를retirement로이동;GPUstorage미반환. |
| waiter notify | :1472 notifyGroupWaiters | 각child.done와queue.idle.notify_all. predicate작성과구별. |
| retirement | :1491 retireIfReady | scheduling+모든feedback+handler종료후에만GPUrelease. signalPending이면GPU만reclaim가능하며semanticcompletion은별도. 모든cleanup이모든completioncallback보다먼저. Completed/pending--후최종notify. |
| feedback | :1686 recordFeedback | group mutex로phase/duplicate/range정합확인→error/feedbackbits기록→현재예비notify→error notification/handlers→retire. |
| signal observer | :1642 recordSignalNotification | generation/Submitted/Pending검사후Succeeded,retire호출. 자체예비notify없음. |
| poison owners | :1656 failSignalNotificationOwners | stateMutex아래firstError/poison/ownertable분리,queueidle즉시notify,group별error·Failed전파/notify/handlers/retire. |
| event registration | :1894 addEvent, :2356 addSignalEvent | childmutex+Recording만허용. signal은value현재검사,operationRetained가event를유지. |
| end | :2664 MVKMetal4Submission::end | Recording→Ended;그뒤addEvent로신호목록변경불가. |
| submit claim | :2719 vector submit | queue.submitMutex아래address-sorted childlocks;모든Ended/owner없음확인후각owner=queue. group.children의작업순서는원래입력순서를유지. |
| precheck | :2887 validGroupSignals 첫호출 | claim후tail/notification준비이전,전체current+상대order검증. |
| publish | :1852 publishPreparedSubmission / :2930 호출 | group→sortedchild→queue잠금. child Ended/owner재검증→validGroupSignals재호출→poison/reservation확인→Submitted/pending증가. |
| semantic ownership cleanup | :1274 clearOperationReferences, :1303 cacheEmptyCompletionStorage | signals/event-owner storage는semanticcompletion 또는Ended취소이후에만정리/이동. prepublish엔변경되지않음. |

public wait는:3058,waitIdle은:3075다. child.done의production대기는wait한곳,queue.idle의대기는waitIdle한곳이다. 성공feedback의workFeedbackDone/rangeFeedback/tailFeedbackDone은이predicate에직접들어가지않는다. 조건변수자체가완료를게시하는것은아니다.

## #6 — 성공 예비 wake만 제거

권고patch의대상은recordFeedback 마지막의무조건notify 한줄뿐이다. 개념상`if (feedback.error) { notifyGroupWaiters(group); }`로바꾸고이어지는failSignalNotificationOwners/runGroupErrorHandlers/retireIfReady순서와모든다른notify호출은그대로둔다. error handler가있는지와무관하게실제error이면notify한다. `if (runErrors)`는틀린조건이다: handler가0개여도publishGroupError가child.error와queue.firstError를게시하여잠든waiter를깨워야한다.

성공branch는grouplock아래feedback완료비트만바꾸며child.phase/error나queue.pending/firstError를아직바꾸지않는다. 따라서예비notify로깨어도두waitpredicate는false다. 진짜완료를만드는retireIfReady는child.phase=Completed 및group/queue완료를각보호mutex아래게시한뒤:1639에서항상notify한다. signalPending/미완료range/submitFinished=false/errorHandlersRunning일때retire가돌아가도어느성공waitpredicate도true가되지않아알림이필요하지않다. Pending상태GPUStorage만Reclaimed로바뀌어도성공wait의계약은아직semanticCompleted다.

다른thread의오류와성공feedback이교차해도오류게시를한경로의알림은그대로다. failSignalNotificationOwners는queue와해당group오류를별도로알리고,recordFeedback(error)도기존예비알림을유지한다. source내부에서predicate를true로바꾸는경로와그알림이짝지어있다는것이핵심증명이며,callback수를단순히줄였다는사실만으로증명하지않는다. group→child/stateMutex순서·allocatorreset·quarantine·notificationGeneration/slots는수정하지않는다.

이작은변경은성공한accepted feedback마다기존Nchildren+1개의notify_all호출을없앨수있다. 실제잠든thread가있는비율이나시간절감을말하는수치는아니다. duplicate/잘못된range/이미Retiring·Completed의feedback은원래earlyreturn하므로바뀌지않는다. finalnotify/errornotify를합치거나notify_one으로바꾸거나notify위치를handler뒤로옮기는것은범위밖이다.

반례와필수일정:

1. signal없음/한range:child.done와queue.idle에실제로대기하는thread를두고work-before-submitFinished 및역순을각각진행한다. 마지막gate전에는반환/cleanup없고마지막gate후둘다deadline내성공반환한다.
2. signalPendingnotification:work+finished후GPUcleanup만실행되고child/idle성공은아직반환하지않아야한다. 실제signalobserver후retire가완료및notify한다. tail경로도work/tail/finish의기존permutation을유지한다.
3. 여러range:모든range가아닌feedback,duplicate,범위밖index는정상완료/자원반환을앞당기지않는다. 마지막validrange뒤최종notify가있어야한다.
4. error+handler0:tail/finish미완료로retire불가능한상태에서errorfeedback을보내잠든childwait와idlewait가error로즉시돌아오되GPUcleanup은0임을확인한다. 이case가잘못된runErrors조건을구별한다.
5. errorhandlerblock:예비errornotify가handler보다먼저있어handler가끝나지않아도waiter는error를관측한다. childerror가mutex아래쓰인것과GPUstorage미반환을확인한다.
6. poison/notificationfailure/동시success+error/중복callback에서firsterror와exactly-oncecleanup/완료/queuepending을보존한다. 이미완료한정상그룹을후속poison이재완료시키지않는다.

기존tools/tests/metal4-recording-group.mm의manualPublication/feedback/finish·gatePermutations/earlyErrorAndPoison/racingTerminalGates와counter-completion-cpu.mm의range/inline/error mock을재사용한다. wait(0)polling만으로는wake검증이되지않는다. CPU만으로도실제std::condition_variable/thread를쓰는관련case를만들수있다. test-only대기helper는childmutex를잡은채ready를게시하고falsepredicate로실제done.wait에들어간다;main은같은mutex를한번획득해worker의atomic-unlock/wait경계가성립했음을확인한뒤락을풀고feedback을보낸다. 이는production과같은field/predicate의프로토콜검증임을명시하고publicwait실제본문의별도source-derivedcase도둔다. 또는test-sideCVwrapper로실제publicwait진입을노출하되새제품collector는넣지않는다. 임의sleep만으로실제로잠들었다고단정하지않는다.

CPU후나중에승인된native검사중기존r49 lifetime idleTimeout/blocked callback/error/notification관련case와recording-group의실제tail/notification한정case가적절하다. CPUfakecallback의순서검증은Metal의실제delivery/프로세스종료증명과다르다. 과거sampled native-exit문제가해결됐다고주장하지않는다. 이문서에서아무case도새로실행하지않았다.

## #7 — immutable 상대 signal-order만 재사용

validGroupSignals는children작업순서/각signals의순서로걷는다. 각signal의validSignalValue(event,value)를먼저검사한뒤,이전모든signal과같은event&&prior.value>=value를검사한다. addEvent의Recording-time현재값검사,첫prep검사,publication현재값재검사는전부서로다른시점이다. 이중두번째publication에서이미증명한상대pair순회만없앨수있다. current signaledValue는MTLSharedEvent외부상태라절대캐시하지않는다. zero value/비sharedMTLEvent/기존오류문구와우선순위도그대로다.

재사용가능한불변근거는이미claim된freshgroup다. childlocks로Ended/owner없음을검사하고owner=queue를기록했으므로다른queue의adoption도거부된다. publicaddEvent는Ended에서거부되고group.children는첫검증이후추가·정렬·삭제되지않는다. stronggroup.children가state를유지하고operationRetained가event를소유한다. cleanup/벡터capacityrecycle은publication및retirement이후여서proof를만드는구간에신호내용이바뀌지않는다. lock주소순서와실제signal작업순서는다르므로pair검증의children순서를address순으로바꾸지않는다.

권고하는정확변경점은모두Submission.mm의내부namespace다. 공개Submission.h나GPU/allocator정책필드는바꿀필요없다.

- `GroupSignalOrderProof`를submit-local 기본invalid타입으로추가한다. `const Group* validatedGroup=nullptr`한개면되고,copy/move를막아장기보관을유도하지않는다. construction에rawpointer를공개하지않고friend검증factory만성공후설정한다. 현재submit의sharedgroup가token보다오래살아주소ABA가없다는명시적스코프를유지한다. token를group/child/pool/notification/callback에저장·캡처하지않는다.
- `validGroupSignals(group,error,proof=nullptr)`로내부helper를좁힌다. 각signal의기존validSignalValue검사는항상먼저수행한다. proof가같은freshgroup를가리킬때만기존nested prior-loop를건너뛴다. 없거나다른group의proof면기존fullcheck다.
- `validateAndProveGroupSignals(group,error,proofOut)`는먼저out를invalid로지우고proof없는기존전체검증을실행한후에만group주소를설정한다. 검증실패시이전성공proof가남지않는다.
- vector submit의기존:2887호출을위factory로바꾸고지역token를만든다. tail/notification준비는원래순서그대로다.
- publishPreparedSubmission에마지막optional `const GroupSignalOrderProof* proof=nullptr`를추가해productioncaller만지역token주소를넘긴다. childphase/owner재검증뒤의validGroupSignals만이token를받는다. 나머지group→child→queue잠금/poison/reservation/Submitted·pending순서는그대로다.

barebool을group에두는안도현재closedcontrolflow에서는성립할수있으나첫검증성공의출처와동일group범위를타입/호출로검수하기어렵고재시도/직접호출에잘못전파되기쉽다. submit-localtoken는새heap/vector/map할당이나shared_ptrrefcount를추가하지않고이범위를드러낸다. groupmutex때문에객체를복사하는안도아니다. long-livedglobalproof·event주소만캐시·단순signal개수만맞는경우재사용·큐전체신뢰flag는기각한다. token에스냅샷vector를복제해상대순회절감을다시지불하는안도권고하지않는다.

오류순서보존을위해첫검증을“모든current를먼저검사,다음에모든pair”의두pass로재배열하지않는다. 기존처럼각signal에서current→prior-loop를수행한다. publication시pair관계는불변이고첫검증에서true였으므로생략후에도나중에바뀐current값실패의첫index/오류3과원문메시지가그대로다. caller가동시에잘못host-signal하는상황전체를새로race-proof하게만든다는주장은하지않는다.

반례와필수일정:

1. zero/one/multi signal,같은event equal/decreasing/increasing,다른event를교차배치,여러child경계·metadata만있는finalchild를기존fullvalidator oracle과비교한다. 첫검증에서실패하면proof는invalid이고hostactions/queueoperations/pending변경0이어야한다.
2. 첫전체검증성공후공유event현재값을target이상으로올린뒤publication하면현재값검사에서여전히실패해야한다. 실제부적격입력거부검사이며그호스트갱신을정상Vulkanschedule이라고주장하지않는다. fakegetter읽기순서또는기존tail-allocation주입위치로두검사사이에걸리도록test만제어한다.
3. signal=0과nonsharedMTLEvent의양수값/반복동일eventpair도원래판정과같아야한다. event타입·conforms검사를캐시하지않는다.
4. direct manualPublication은token없이기존fullvalidator를탄다. invalidorderedgroup는반드시거부한다. wrong-group token역시fullfallback이며한group의성공으로다른group를신뢰하면안된다.
5. tail준비실패/notification등록실패후새submit으로재시도하면freshgroup/freshtoken으로재검증한다. Endedownerrollback·weaknotifygeneration·claim해제를원래대로확인한다. 같은rawchild주소/pool용량재사용이token재사용허가가되지않는다.
6. token획득후childphase/owner가syntheticfixture에서변하면publication의선행guard가여전히실패한다. production에서는Ended의신호API변경시도가거부됨을확인한다. 테스트가privatevector를임의편집하고같은token로order를생략하는것은production불변계약위반이며허용동작으로인증하지않는다;그런mutator를제품에추가하려면proof를다시설계해야한다.
7. full oracle과proven-publication의current검사횟수는동일하고두번째pair비교만줄어드는것을test-onlyeventgetter/비교wrapper로구별한다. 새제품counter는넣지않는다. 실제multi-signal비율/FPS/CPU시간은아직미확정이며,0/1개signal에서는혜택이매우작을수있고token분기비용도있다.

기존recording-group.mm:194 orderedSignals와:215 preparationFailure, :801 manualPublication이직접관련된다. ownership.mm:80 obsolete signal rejection은첫검사거부를기존대로유지하는검사이고,두시점사이현재값변경case를추가해야두번째검사보존을증명한다. 실제native orderedSignals한정readback/tail관련case는후일승인된실행에서유효하지만source-only지금은실행하지않는다.

## 구현·검수·철회 순서

1. 먼저각각별도before/afterpayload와exactpatch를만들고sharedSubmission원본핀을두부모에명시한다. #6과#7은같은파일의다른구간이므로fullafter순서핀은별도다. #6을#7proof의전제나반대로만들지않는다.
2. 변경source독립검수→각한정source-derivedCPUcase→기존관련fixture의선택case순이다. foundationOFF에nativeM4를가정하지않고ON/OFF문법구성만분리한다. 이단계CPU만으로실GPU완료·nativecallback스케줄·공정FPS검증을대체하지않는다.
3. 실제적용/관련증분빌드/native스모크/서명앱·동일조건비교는후일큐사인의범위안에서root가수행한다. source-only준비와이미검증·승격을구분한다. 새전체suite/collector가자동선행조건은아니다.
4. #6철회는예비notify한곳을무조건호출로되돌리는것뿐이고, #7철회는factory/token전달을없애기존두전체검증으로돌리는것이다. 최종/errornotify·liveevent검사·GPUstorage gate를철회대상으로섞지않는다.

source만으로닫힌것은수정대상의predicate·변경점·소유불변·직접callerfallback·반례설계다. 실제잠든thread의wake/에러진행·Metal실callback의대체진행보장·수정된코드의컴파일/검사통과와순이익은아직증거가없다. 구현불가라서짧은gate문서만남기는대신위정확패치와관련스케줄을준비할수있다는결론이다. 현재수명/오류/메모리불변을약화해야만이득이생기는설계로확장하면중단해야한다.

읽은source/fixture핀은동반JSON에있다. source·fixture·build·앱·runner를수정하거나CPU/GPU/빌드/게임/OS/서비스/원격작업을실행하지않았고이설계두파일만작성했다. 기존scope/module검수기록도바꾸지않았다.
