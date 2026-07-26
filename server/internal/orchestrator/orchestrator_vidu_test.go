package orchestrator

import (
	"context"
	"sync"
	"testing"
)

type fakeViduRuntime struct {
	mu        sync.Mutex
	connected bool
	closed    bool
	texts     []string
}

func (f *fakeViduRuntime) Connect(context.Context) error {
	f.mu.Lock()
	f.connected = true
	f.mu.Unlock()
	return nil
}

func (f *fakeViduRuntime) SendText(text string) error {
	f.mu.Lock()
	f.texts = append(f.texts, text)
	f.mu.Unlock()
	return nil
}

func (f *fakeViduRuntime) Close(context.Context) error {
	f.mu.Lock()
	f.closed = true
	f.connected = false
	f.mu.Unlock()
	return nil
}

func (f *fakeViduRuntime) Ready() bool {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.connected && !f.closed
}

func TestViduSessionRoutesTextAndClosesOnTeardown(t *testing.T) {
	sessionMgr := NewSessionManager(1)
	t.Cleanup(sessionMgr.Stop)
	session, err := sessionMgr.Create("session-vidu", ModeStandard, "character-vidu")
	if err != nil {
		t.Fatal(err)
	}
	orch := New(nil, nil, sessionMgr, nil, nil)
	runtime := &fakeViduRuntime{}
	orch.RegisterViduSession(session.ID, runtime)

	handled, err := orch.ConnectViduSession(context.Background(), session.ID)
	if err != nil || !handled || !orch.ViduSessionReady(session.ID) {
		t.Fatalf("connect handled=%v ready=%v err=%v", handled, orch.ViduSessionReady(session.ID), err)
	}
	handled, err = orch.SendViduTextInput(session.ID, "wave hello")
	if err != nil || !handled {
		t.Fatalf("send handled=%v err=%v", handled, err)
	}
	if len(runtime.texts) != 1 || runtime.texts[0] != "wave hello" {
		t.Fatalf("texts=%v", runtime.texts)
	}
	_, _, _, _, messages := session.ConversationSnapshot()
	if len(messages) != 1 || messages[0].Role != "user" || messages[0].Content != "wave hello" {
		t.Fatalf("messages=%v", messages)
	}

	if err := orch.TeardownSession(session.ID); err != nil {
		t.Fatal(err)
	}
	if !runtime.closed {
		t.Fatal("expected Vidu runtime to close during session teardown")
	}
	if orch.ViduSessionReady(session.ID) {
		t.Fatal("expected Vidu runtime to be removed after teardown")
	}
}
