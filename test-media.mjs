import { getCurrentSession, listSessions } from 'win-media-control-enhanced';

async function test() {
  try {
    console.log("Fetching active sessions...");
    const sessions = await listSessions();
    console.log("Sessions:", sessions);

    console.log("Fetching current session...");
    const current = await getCurrentSession();
    console.log("Current:", current);
  } catch (e) {
    console.error("Error:", e);
  }
}

test();
