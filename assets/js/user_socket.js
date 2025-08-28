// NOTE: The contents of this file will only be executed if
// you uncomment its entry in "assets/js/app.js".

// Let's use the Phoenix Socket to connect to our channel
import {Socket} from "phoenix"

let socket = new Socket("/socket", {params: {token: window.userToken}})

// When you connect, you'll often need to authenticate the client.
// For example, imagine you have an authentication plug, `MyAuth`,
// which authenticates the session and assigns a `:current_user`.
// If the current user exists you can assign the user's token in
// the connection for use in the layout.
//
// In your "lib/my_app_web/endpoint.ex":
//
//     socket "/socket", MyAppWeb.UserSocket,
//       websocket: [
//         check_origin: false,
//         connect_info: [session: @session_options]
//       ]
//
// In your "lib/my_app_web/channels/user_socket.ex":
//
//     def connect(%{"token" => token}, socket, _connect_info) do
//       # max_age: 1209600 is equivalent to two weeks in seconds
//       case Phoenix.Token.verify(socket, "user socket", token, max_age: 1_209_600) do
//         {:ok, user_id} ->
//           {:ok, assign(socket, :current_user, user_id)}
//
//         {:error, reason} ->
//           :error
//       end
//     end
//
// You may also be forced to pass a `connect_info` map
// containing the endpoint, transport, and params. In this case,
// you can use `socket.connect_info` to get the connection data.
//
// Finally, connect to the socket:
socket.connect()

// Now that you are connected, you can join channels with a topic.
// Let's assume you have a channel with a topic named `"room"` and the
// subtopic is its id - in this case 42:
//
//     let channel = socket.channel(`room:${id}`, {})
//     channel.join()
//       .receive("ok", resp => { console.log("Joined successfully", resp) })
//       .receive("error", resp => { console.log("Unable to join", resp) })
//
// export the socket to be imported in app.js
export default socket
