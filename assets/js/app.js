import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken}
})

window.addEventListener("phx:scroll_into_view", (event) => {
  const el = document.getElementById(event.detail.id)
  if (el) el.scrollIntoView({behavior: "smooth", block: "center", inline: "nearest"})
})

liveSocket.connect()
