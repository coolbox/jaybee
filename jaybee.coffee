# Collections
#
@PlaylistTracks = new Meteor.Collection("playlist_tracks")

# Functions
#
play = (id) ->
  track = PlaylistTracks.findOne id

  # Play it
  SC.stream "/tracks/#{track.track_id}", (sound) ->
    # Stop anything thats playing
    soundManager.stopAll()

    # Set Session sound
    Session.set("now_playing_sound", sound)

    # Start playing the track
    sound.play
      onfinish: playNext
      whileplaying: ->
        # elapsed track, @position

playNext = ->
  # Clear the currently playing Session data
  clearPlaying()

  track = nextTrack()

  if track
    markAsNowPlaying track
  else
    console.log "Add a track to the playlist"

elapsed = (track, position) ->
  console.log position, track.position
  if position > track.position
    PlaylistTracks.update track._id,
      $set:
        position: position

  console.log position
  elapsed_time = track_length position
  Session.set "local_elapsed_time", elapsed_time

togglePause = ->
  now_playing_sound = Session.get("now_playing_sound")
  soundManager.togglePause(now_playing_sound.sID)

clearPlaying = ->
  # Clear Sound Manager sound from session
  # Session.set("now_playing_sound", null)
  # console.log("now_playing_sound", Session.get("now_playing_sound"))

  # Clear local time position
  # Session.set("local_track_position", null)
  # console.log("local_track_position", Session.get("local_track_position"))

  # Mark track as not playing
  track = nowPlaying()
  if track
    PlaylistTracks.remove(track._id)
  # console.log("Now playing (should be null): ", nowPlaying())

nextTrack = ->
  # PlaylistTracks.findOne({now_playing: false}, {sort: [["created_at", "asc"]]})
  PlaylistTracks.findOne {now_playing: false}, 
    sort: [["created_at", "asc"]]

nowPlaying = ->
  # PlaylistTracks.findOne({now_playing: true}, {sort: [["created_at", "asc"]]})
  PlaylistTracks.findOne {now_playing: true},
    sort: [["created_at", "asc"]]

markAsNowPlaying = (track) ->
  # PlaylistTracks.update(track._id, {$set: {now_playing: true}})
  PlaylistTracks.update track._id,
    $set:
      now_playing: true

volumeUp = ->
  sound = Session.get("now_playing_sound")
  if sound
    sound = soundManager.getSoundById(sound.sID)
    volume = sound.volume
    if volume < 100
      sound.setVolume(volume + 10)

volumeDown = ->
  sound = Session.get("now_playing_sound")
  if sound
    sound = soundManager.getSoundById(sound.sID)
    volume = sound.volume
    if volume > 0
      sound.setVolume(volume - 10)

toggleMute = ->
  sound = Session.get("now_playing_sound")
  if sound
    sound = soundManager.getSoundById(sound.sID)
    volume = sound.volume
    if volume is 0
      pre_mute_volume = Session.get("pre_mute_volume") || 80
      sound.setVolume(pre_mute_volume)
    else
      Session.set("pre_mute_volume", volume)
      sound.setVolume(0)

addToPlaylist = (track_id) ->
  SC.get "/tracks/#{track_id}", (track) ->
    PlaylistTracks.insert
      track_id: track.id
      title:    track.title
      username: track.user.username
      duration: track.duration
      artwork_url: track.artwork_url
      position: 0
      now_playing: false
      created_at: timestamp()

search = (search_query) ->
  page_size = 20
  SC.get "/tracks", 
    q: search_query,
    filter: "streamable", 
    limit: page_size, (tracks) ->
      Session.set("search_results", tracks)

clearSearch = ->
  Session.set("search_results", null)  

track_length = (duration) ->
  seconds = parseInt((duration/1000)%60)
  minutes = parseInt((duration/(1000*60))%60)
  hours   = parseInt((duration/(1000*60*60))%24)

  hours   = if hours < 10 then "0" + hours else hours
  minutes = if minutes < 10 then "0" + minutes else minutes
  seconds = if seconds < 10 then "0" + seconds else seconds
  
  duration_string = ""
  duration_string += "#{hours}:" unless hours == "00"
  duration_string += "#{minutes}:#{seconds}"

  return duration_string

timestamp = ->
  new Date()

# Client
#
if Meteor.isClient
  Meteor.autosubscribe () ->
    PlaylistTracks.find().observeChanges
      changed: (id, fields) ->
        if fields.now_playing and fields.now_playing == true
          play id

  # Search
  Template.search.events 
    "keyup input.search": (event) ->
      query = event.currentTarget.value
      if query then search query else clearSearch()
      return

  # Search Results
  Template.searchResults.events 
    "click a": (event) ->
      event.preventDefault()
      addToPlaylist event.currentTarget.dataset.trackId
      return

  Template.searchResults.results = ->
    return Session.get("search_results")

  Template.searchResults.length = (duration) ->
    return track_length(duration)

  # Playlist
  Template.playlist.tracks = ->
    return PlaylistTracks.find {now_playing: false}, 
      sort: [["created_at", "asc"]]

  Template.playlist.length = (duration) ->
    return track_length(duration)

  # Controls
  Template.controls.events 
    "click [data-control=play]": (event) ->
      event.preventDefault()
      play nowPlaying()._id
      return

    "click [data-control=pause]": (event) ->
      event.preventDefault()
      togglePause()
      return

    "click [data-control=next]": (event) ->
      event.preventDefault()
      playNext()
      return

    "click [data-control=volume-up]": (event) ->
      event.preventDefault()
      volumeUp()
      return

    "click [data-control=volume-down]": (event) ->
      event.preventDefault()
      volumeDown()
      return

    "click [data-control=mute]": (event) ->
      event.preventDefault()
      toggleMute()
      return

    # Controls
    Template.controls.now_playing = ->
      return nowPlaying()

    Template.controls.length = (duration) ->
      return track_length(duration)

    Template.controls.elapsed = ->
      return Session.get("local_elapsed_time")

# Server
#
if Meteor.isServer
  Meteor.startup ->