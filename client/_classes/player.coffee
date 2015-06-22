class window.Player
  constructor: ->
    # console.log "Player class"

  search: (search_query, page_size = 20) ->
    SC.get "/tracks", 
      q: search_query,
      filter: "streamable, public",
      limit: page_size, (tracks) ->
        Session.set("search_results", tracks)

  addToPlaylist: (track_id) ->
    SC.get "/tracks/#{track_id}", (track, error) ->
      if error
        Meteor.Error(404, error.message)
      else
        console.log "Client:", track
        Meteor.call 'addToPlaylist', track

  removeFromPlaylist: (track_id) ->
    Meteor.call 'removeFromPlaylist', track_id

  favourite: (track_id) ->
    SC.put "/me/favorites/#{track_id}", (response) =>
      console.log response
      favourites = Session.get 'sc.favorites'
      newFavs = @arrayUnique(favourites.concat([parseInt(track_id)]))
      Session.set 'sc.favorites', newFavs

  unFavourite: (track_id) ->
    SC.delete "/me/favorites/#{track_id}", (response) =>
      favourites = Session.get 'sc.favorites'
      newFavs = @arrayUnique(_.without(favourites, parseInt(track_id)))
      Session.set 'sc.favorites', newFavs

  getFavorites: (offset = 0, limit = 200) ->
    offset = offset
    limit = limit
    favorites = Session.get 'sc.favorites'

    unless favorites
      Session.set 'sc.favorites', null
    
    SC.get "/me/favorites", {offset: offset, limit: limit}, (response, error) =>
      # Error?
      if error
        return

      # array of id's
      # [1,2,3,4] etc
      favorites = Session.get 'sc.favorites'
      favorites = if favorites == null then [] else favorites
      response.forEach (track) ->
        favorites.push track.id

      Session.set 'sc.favorites', @arrayUnique(favorites)

      if response.length > 0
        offset = offset + limit
        @getFavorites offset

  arrayUnique: (array) ->
    a = array.concat()
    i = 0

    while i < a.length
      j = i + 1

      while j < a.length
        a.splice j--, 1  if a[i] is a[j]
        ++j
      ++i
    a

  inFavorites: (track_id) ->
    favorites = Session.get('sc.favorites')
    if favorites
      return _.find Session.get('sc.favorites'), (track) ->
        if track.id == track_id
          return track

  accessToken: ->
    return Meteor.user().services.soundcloud.accessToken

  track_length: (duration) ->
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

  play: (track) ->
    console.log "play"
    playerInstance = @

    # Play it
    SC.stream "/tracks/#{track.track_id}", (sound, error) ->
      # Stop anything thats playing
      soundManager.stopAll()
      Session.set "currentSound", sound

      # If joining a session and the player
      # is already playing, match the new
      # client to the currently playing position
      # sound.setPosition(5000) if position > 0

      # Start playing the track
      sound.play
        whileplaying: ->
          playerInstance.elapsed track, @position
          playerInstance.toggleMute @
          playerInstance.setVolume @
        onload: ->
          if @readyState == 2
            console.warn "There was a problem with the track.", @
            playerInstance.playNext()
        onfinish: ->
          playerInstance.playNext()

  playNext: ->
    Meteor.call "nextTrack", (error, track) =>
      if track
        # Add to history
        Meteor.call "addToHistory"

        # Clear the currently playing Session data    
        Meteor.call "clearPlaying"

        Meteor.call "markAsNowPlaying", track
          
        # @play track
      else
        console.log "Add a track to the playlist"

  elapsed: (track, position) =>
    elapsed_time = @track_length(position)

    # This is to prevent the timer
    # from gibbing out as we update across
    # multiple clients.
    Session.set "local_elapsed_time", elapsed_time

  toggleMute: (sound) ->
    listening = Session.get "muted"
    
    if listening and sound.muted
      sound.unmute()
    else if !listening and !sound.muted
      sound.mute()

  setVolume: (sound) ->
    volume = Session.get "volume"   
    sound.setVolume volume
