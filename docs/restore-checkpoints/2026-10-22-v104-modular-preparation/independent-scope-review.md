현재 준비 가능한 새 코드 모듈은 **11a와 보수적인2837의 두 좁은 하위안**이다. 원래13개 모두가 안전한 완성패치13개라는 뜻은 아니다. #1의bounded reserve는이미Small에구현·관련검증됐지만R선택에는승격되지않았고원본8회FPS는adoption제외다. 나머지원안의설계보류를“큐사인만오면모두자동적용”으로표시하면안된다.

| 원번호 | 범위 | 현재 분류 |
| --- | --- | --- |
| 1 | proof/snapshot 임시 배열 | Small의16상한·첫유효proof이후reserve 단위는구현/관련검증완료. R에는없고일반SBO/추가공유는완료아님. 기존Small을재사용하고중복새패치금지. |
| 2 | layout 조기 적격성 분류 | Zink push-template가먼저Deferred로전환하는관측prefix에서는후속정책조회비도달. #4를강제로켜기위한선행패치로만들지않음. |
| 3 | fallback vector 연결목록 | 원vector capacity재사용은완료. 명령보유node와pool/free-list 소유·prefix복원·취소순서가미설계. |
| 4 | compact UBO 조기 CPU 기록 | mapped최신입력·layout소유·기록시점·late query/fallback을닫고총작업감소가능범위를정해야함. #2/#3와상호작용. |
| 5 | no-conversion lookahead 생략 | 첫draw/pipeline만으로skip불가. whole-pass negative proof와dynamic topology/unknown/write/2048경계가정의돼야함. |
| 6 | 완료 전 예비 notify 축소 | 작은코드라도실제sleeping waiter와success/error/poison/final완료의notify인과가먼저닫혀야함. 과거종료실패수정을주장하지않음. |
| 7 | 불변 signal 순서 proof 재사용 | 원칙상작은후속후보지만proof전달·불변signals소유·직접publication/no-first-check경로설계아직없음. live event값검사는계속유지. 이번코드모듈범위에서제외. |
| 8 | 기록 간 부분 snapshot 확대 | 기존snapshot/weakproof/현재recording retain은완료. 추가partial miss구제는미설계. 인접2837 rebind는별도보수적소형모듈로준비가능하며partial확대완료로세지않음. |
| 9 | per-binding snapshot 잠금 축소 | group밖retain은기존완료. per-binding해제후entry수명/동시교체/conditionalerase와shared_ptr비용검토필요. |
| 10 | allocator 성장·풀·idle 추가조정 | Q reset/R idle-first완료,32→64는기존E실험. 현재32/2MiB/8/64MiB유지. 근거없는상수복사나새allocatorcollector없음. |
| 11 | 불필요 pass 종료·재시작 감소 | 일반pass합침/fragment경계제거는아직미정의. 11a Typed frame-local orphan만기존미적용제안·계약이정의돼작은payload준비가능. |
| 12 | 중간 MSAA resolve 생략 | intermediate/finalfragment·no-next-draw최종resolve·memoryless/private·query예외를설계해야함. AAOff/window샘플0은offscreen경로부재증명아님. |
| 13 | 추가 barrier/GPU wait 중복 축소 | E3제한compute prior coverage는Combined의완료분기이며R에채택된것아님. 정확한중복dependencyedge없이는대기/완료gate삭제불가. |

번호11a는원#11과관련있는상위엔진의frame-local buffer orphan하위안이고,보수적2837은원#8인접rebind하위안이다. 일반pass병합이나부분snapshot확대자체를구현했다고세지않는다. 기존inventory/외부보고서의“workingSource R+lookup”표시는작성당시이력이며현재활성소스는검증된Small(R+reserve)이다. 현재선택앱은R이며,두앱/활성lane는이번준비중동결한다.

11a의기존미적용patch6708badf0af62cc4fb6b336cd7bccba81d5e3f93c229b8459bf4b10684d2f0d6는설계참고다. 최신root는더좁은DSA-only제안을준비하므로그옛patch를새모듈최종핀이라고하지않는다. 두엔진lane의IStreamBuffer에별도Invalidate기본no-op를두고BufferSubData만override하며,non-readonlyTypedSwap에서만Swap→Invalidate→기존Clear를수행한다. 일반SwapBuffer/ModelDataUploader/값보존사용자·persistent/ring·readOnly는그대로다. 유효한nonzero upload가없으면orphan하지않고같은프레임DrawElementsRange/CopyCurrent를건드리지않는다. GL_ELEMENT_ARRAY_BUFFER Bind/Unbind로VAO를교란하는외부원패치는사용하지않는다. 최신DSA-only안은DSA(core4.5또는ARB_direct_state_access)&&nonnullglNamedBufferData일때만orphan하고미지원때no-op이다. COPY_WRITEfallback/상태조회/새binding변경은넣지않아도된다. HEADLESS에서새GL심볼/기능검사호출을완전히제외한다. Invalidate요청뒤에는지원여부와무관하게uploadedSinceInvalidate를비우는편이오래된upload를반복판정하지않아단순하다. 이전GPUbacking생존과새allocation이늘수있어메모리순이익을가정하지않는다.

보수적2837은고정PR5978a64ae125333457ebc35ab1f80321a7eb3924를그대로적용하지않는다. legacyimplicit의실제offset값·유효길이·packing이같다고증명되는경우의dirty처리만좁힌다. resize전에새의미범위/길이증가를dirty로잡고,layout/packing연관성이불명확하면원래clear를유지한다. 기존buffer capacity나같은값0은“이미Metal에같은길이bytes가설정됐다”의증명이아니다. 이전두word[0,0]에서prefixlayout변경후세word[0,0,0]이필요한compute반례를반드시보존한다. common._layout은pipelinebind가이미갱신했을수있어이전descriptorbind packing의memo로무조건쓸수없다.

same set pointer만으로affected resourceUse clear를생략하지않고,현재descriptorpayload/retention/residency검사를유지한다. 포인터비교를도입하면배열을명시초기화하고incarnation/revision을사용한다면이전값을보관해야하지만,첫모듈은새stamp의공통화보다기존affectedclear유지가낮은위험이다. 새encoderreset/helper의argumentroot복구와M4세별도implicit invalidation은유지한다. 따라서M3/legacy경로에만효과가날수있으며nativeM4 implicit비용개선으로포장하지않는다. foundationOFF/M3/nativeM4는독립구성이며OFF+nativeM4제공을가정하지않는다.

의존·충돌은두층으로기록해야한다. 11a와2837은제품파일수준에서겹치지않으므로서로선행필수는아니다. 그러나11a는상위업로드/driver부하분포를바꿀수있으므로성능효과독립·가산·시너지를가정하지않는다. 2837과기존#1은같은MVKCommandEncoderState.mm을만지므로R용before9b28…과Small용beforeb101…를각각정확핀으로묶어야한다. 관련hunk가달라도fullafter핀/rollback이같다는뜻은아니다. Smallreserve를지우거나R에무단추가하지않고,현재lane를R기반proposal로덮어쓰지않는다. D/E/Combined/lookup은이번부모가아니며그버전의긴파일을통째로복사해끼워넣지않는다.

#2는#4를바꾸면도달성이달라질수있지만지금의보류가자동해제되지는않는다. #3/#4는command소유·재생순서가겹치고,#8/#9는snapshot entry소유설계를공유한다. #6/#7/#13은Submission의검증/완료상태를공유하므로동시에묶어개별증명을대체하지않는다. #5/#11/#12/#13은pass분할구간과dependency/query/resolve에교차영향이있다. #10은이들변경의submission분포에영향받으며Q/R수명gate/상수는이번에유지한다.

모듈준비는기존활성파일에쓰기없이root소유의작은before/afterpayload와patch로만수행할수있다. 각모듈은ID/출처고정commit/부모variant R또는Small/대상파일별원본bytes·mode·SHA256/afterSHA/patchSHA/사전조건/함께쓰면안되는모듈/철회경로/나중의관련검증계획을가져야한다. 패치문맥exact·fuzz0의메모리상재구성으로before→after가맞음을확인하고,알수없는현재핀·재적용·경로이탈·누락파일이면거부한다. 임시검사용copy를build/source아래에두거나livefixture를고치지않고,evidence하위payload만편집한다. diff적용만으로C++컴파일·GPU수명·성능검증통과라고표시하지않는다.

같은파일모듈을나중에묶을때는정해진순서와단계별fullSHA를검증하고,역순도가능하다고주장하려면두순서결과동등을별도로증명해야한다. copy2로옛mtime를활성header에복원해잔존ABI오브젝트가생긴이력을반복하지않는다. 큐사인후실제적용할때11a의virtual추가가포함된두native의dependentTU를freshmtime로관련재빌드하고,선택된부모앱의MVK바이트를보존한다. engine-only11a앱에activeSmallraw를무심코넣어R과섞으면안된다.

나중의최소관련검증은새로수행한것이아니다. 11a는생산Stream/Typed본문을쓰는기존fixture의target별binding/VAO/fakebackinggeneration·DSA/nullptr/capability/unsupported/HEADLESS·readOnly/partial/zero-upload/copy/move/Model값보존과unsafe원패치음성대조가적절하다. Chobby에없는RangeAPI를새로만들어검증했다고하지않는다. 2837은offset0/값변경/길이증가all-zero/packing전환·부분bind·다중set/stage·새encoder/helper·현재resourceclear유지와foundationOFF/ONM3/M4분기를보는관련기존검사계획이면된다. non-UAB업데이트로Vulkancommandbuffer를불법무효화한예를실제버그재현이라고하지않는다. 원본suite전체/새collector는선행요구가아니다.

제안한상태는“코드작성가능→미적용소스검수완료→후일관련검증대기”이며출시ready와구별한다. 현재모듈큐에는11a와보수적2837만조건부포함하고,기존Small재사용은별도선택옵션,설계보류항목은자동queue에서제외하는편이정확하다. 이번검수에서는새코드패치·활성source/fixture/build/app수정·test/build/GPU/게임/벤치·새agent/chat·OS/service조작·remote쓰기·삭제를수행하지않았다. 기존지정근거를읽고이두독립scope파일만작성했다.

추가설계의견: 현재bindGraphicsPipeline/bindComputePipeline는descriptorimplicit3종을명시적으로무효화하지않고PushConstant길이증가만처리한다. 2837에서반복clear를생략하려면pipeline또는layout변경때legacyBufferSize/DynamicOffset/Swizzle을보수적으로invalidate하는보완이필요하다. 모든implicit종류의기존정책까지넓히지않는다. 새rawlayout수명memo를피하는더좁은gate는currentpipeline가있고이번bindlayout이기존current_layout과동일할때만실제값/새범위비교의unchanged결과를skip에사용하는것이다. 다르거나unknown이면원clear를유지한다. pipeline전환시실제layout길이가바뀌는all-zero반례와descriptorbind-before/afterpipelinebind순서를모두고려하고,새encoderreset/compute↔graphicshelper전환의기존무효화를유지한다. 이gate와pipeline보완은설계의견이며최종patch가준비되면다시소스검수해야한다.
