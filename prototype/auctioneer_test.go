package prototype

import (
	"testing"
)

type mockSequencer struct{}

// TODO: Mock sequencer subscribes to auction resolution events to
// figure out who is the upcoming express lane auction controller and allows
// sequencing of txs from that controller in their given round.

// Runs a simulation of an express lane auction between different parties,
// with some rounds randomly being canceled due to sequencer downtime.
func TestCompleteAuctionSimulation(t *testing.T) {
}
