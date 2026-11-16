// Copyright Stichting LibreKAT. EUPL-1.2.
#include "../capture_startup_state.h"

#include <cstdlib>
#include <future>
#include <memory>
#include <thread>

using ocideck::CaptureStartupState;
using namespace std::chrono_literals;

void Require(bool condition) {
  if (!condition) std::abort();
}

// De worker gebruikt de echte gedeelde starttoestand nog nadat de UI zijn
// eigenaarschap heeft losgelaten. Gates maken de oude foutvolgorde stabiel.
void SuccessfulStartRetainsWorkerOwnership() {
  auto state = std::make_shared<CaptureStartupState>();
  std::weak_ptr<CaptureStartupState> observed = state;
  std::promise<void> resume;
  auto gate = resume.get_future();
  std::thread worker([owned = state, gate = std::move(gate)]() mutable {
    owned->Publish({0, 48000, 2});
    gate.wait();
    const auto result = owned->WaitFor(0ms);
    Require(result && result->sample_rate == 48000 && result->channels == 2);
  });
  const auto result = state->WaitFor(2s);
  Require(result && result->status == 0);
  state.reset();
  Require(!observed.expired());
  resume.set_value();
  worker.join();
  Require(observed.expired());
}

void TimedOutStartStillAllowsLatePublication() {
  auto state = std::make_shared<CaptureStartupState>();
  std::weak_ptr<CaptureStartupState> observed = state;
  std::promise<void> finish_initialization;
  auto gate = finish_initialization.get_future();
  std::thread worker([owned = state, gate = std::move(gate)]() mutable {
    gate.wait();
    owned->Publish({-1, 0, 0});
    Require(owned->WaitFor(0ms)->status == -1);
  });
  Require(!state->WaitFor(1ms));
  state.reset();
  Require(!observed.expired());
  finish_initialization.set_value();
  worker.join();
  Require(observed.expired());
}

int main() {
  for (int i = 0; i < 100; ++i) {
    SuccessfulStartRetainsWorkerOwnership();
    TimedOutStartStillAllowsLatePublication();
  }
  CaptureStartupState state;
  state.Publish({-1, 0, 0});
  state.Publish({0, 16000, 1});
  Require(state.WaitFor(0ms)->status == -1);
  return 0;
}
