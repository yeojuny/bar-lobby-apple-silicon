
#include <algorithm>
#include <array>
#include <cassert>
#include <cstdint>
#include <cstdio>
#include <vector>
static int checks = 0;
static void check(bool ok) { ++checks; if (!ok) { std::fprintf(stderr,"failed check %d\n",checks); std::abort(); } }

struct Pool;
struct MVKCommand { MVKCommand* _next=nullptr; int id=0,returns=0; Pool* pool=nullptr;
    Pool* getTypePool(Pool*) {return pool;} };
struct Pool { std::vector<int> returned;
    void returnObject(MVKCommand* x) {check(++x->returns==1);returned.push_back(x->id);x->_next=x;}
    void returnObjectAsync(MVKCommand* x) {returnObject(x);} // Immediately reuses the link.
};
struct Buffer {
    Pool pool; MVKCommand* _head=nullptr;MVKCommand* _tail=nullptr;
    MVKCommand* _metal4PreparedReplayHead=nullptr;MVKCommand* _metal4PreparedReplayTail=nullptr;
    MVKCommand* _metal4PreparedTimestamp=nullptr; bool _metal4RetainPreparedReplay=false;
    Pool* getCommandPool() {return &pool;}
    void releaseCommands(MVKCommand*,bool=false);void releaseRecordedCommands(bool=false);
    void releaseMetal4PreparedReplay(bool=false);void restoreMetal4PreparedReplay();
    // Native encoder/context destruction is outside this CPU shell. The actual
    // clear method calls this same replay-release method after disposing them.
    void clearMetal4PreparedRecording(){releaseMetal4PreparedReplay();}
};

void Buffer::releaseCommands(MVKCommand* command, bool asyncReturn) {
    while(command) {
        MVKCommand* nextCommand = command->_next; // Establish next before returning current to pool.
#if MVK_BUILD_METAL4_FOUNDATION
        if (_metal4RetainPreparedReplay) {
            command->_next = nullptr;
            if (_metal4PreparedReplayTail) { _metal4PreparedReplayTail->_next = command; }
            else { _metal4PreparedReplayHead = command; }
            _metal4PreparedReplayTail = command;
            command = nextCommand;
            continue;
        }
#endif
        auto* pool = command->getTypePool(getCommandPool());
        if (asyncReturn) { pool->returnObjectAsync(command); }
        else { pool->returnObject(command); }
        command = nextCommand;
    }
}
void Buffer::releaseRecordedCommands(bool asyncReturn) {
    releaseCommands(_head, asyncReturn);
	_head = nullptr;
	_tail = nullptr;
}
void Buffer::releaseMetal4PreparedReplay(bool asyncReturn) {
    _metal4RetainPreparedReplay = false;
    _metal4PreparedTimestamp = nullptr;
    auto* head = _metal4PreparedReplayHead;
    _metal4PreparedReplayHead = _metal4PreparedReplayTail = nullptr;
    // releaseCommands saves each successor before an async pool reuses _next.
    releaseCommands(head, asyncReturn);
}
void Buffer::restoreMetal4PreparedReplay() {
    // Restore the exact original prefix before the unencoded suffix. Nothing
    // has been published by the prepared timestamp when activation rejects it.
    _metal4RetainPreparedReplay = false;
    _metal4PreparedTimestamp = nullptr;
    if (_metal4PreparedReplayHead) {
        _metal4PreparedReplayTail->_next = _head;
        if (!_tail) { _tail = _metal4PreparedReplayTail; }
        _head = _metal4PreparedReplayHead;
    }
    _metal4PreparedReplayHead = _metal4PreparedReplayTail = nullptr;
    clearMetal4PreparedRecording();
}

static std::vector<int> order(MVKCommand* p,size_t cap) {
    std::vector<int> result;
    while(p){check(result.size()<cap);result.push_back(p->id);p=p->_next;}return result;
}
int main(){
  for(size_t count:{size_t(0),size_t(1),size_t(2),size_t(257)})
   for(size_t suffix:{size_t(0),size_t(1),size_t(5)})
    for(bool restore:{false,true}) for(bool async:{false,true}) {
      Buffer b;std::vector<MVKCommand> nodes(count+suffix);std::vector<int> expected;
      for(size_t i=0;i<nodes.size();++i){nodes[i].id=i;nodes[i].pool=&b.pool;expected.push_back(i);}
      b._metal4RetainPreparedReplay=true;
      // One completed staged pass may be traversed repeatedly for multiview
      // before transfer. The transfer occurs only after the last traversal.
      size_t split=count/2;
      for(size_t first=0;first<count;){size_t end=first==0&&split?split:count;
        for(size_t i=first;i+1<end;++i)nodes[i]._next=&nodes[i+1];
        auto before=order(&nodes[first],count+1);
        check(order(&nodes[first],count+1)==before);
        b.releaseCommands(&nodes[first]);first=end;
      }
      check(b.pool.returned.empty());
      check(order(b._metal4PreparedReplayHead,count+1)==std::vector<int>(expected.begin(),expected.begin()+count));
      if(count){check(b._metal4PreparedReplayTail==&nodes[count-1]);check(!b._metal4PreparedReplayTail->_next);}
      if(suffix){b._head=&nodes[count];b._tail=&nodes.back();
        for(size_t i=count;i+1<nodes.size();++i)nodes[i]._next=&nodes[i+1];}
      if(restore){
        b.restoreMetal4PreparedReplay();
        check(order(b._head,nodes.size()+1)==expected);
        check(!b._metal4PreparedReplayHead&&!b._metal4PreparedReplayTail);
        check(b.pool.returned.empty());
        // A later suffix pass can still use its own ordinary chain.
        if(suffix)check(order(&nodes[count],suffix+1)==std::vector<int>(expected.begin()+count,expected.end()));
        b.releaseRecordedCommands(async);
      }else{b.releaseMetal4PreparedReplay(async);b.releaseRecordedCommands(async);}
      check(b.pool.returned==expected);
      b.releaseMetal4PreparedReplay(async);b.releaseRecordedCommands(async);b.restoreMetal4PreparedReplay();
      check(b.pool.returned==expected);
      check(!b._head&&!b._tail&&!b._metal4PreparedReplayHead&&!b._metal4PreparedReplayTail);
      for(auto& n:nodes)check(n.returns==1);
    }
  std::printf("{\"status\":\"passed\",\"checks\":%d,\"actualGPU\":false}\n",checks);
}
