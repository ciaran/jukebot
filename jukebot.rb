require 'rbosa'
require File.dirname(__FILE__) + '/playlist'

$VERBOSE = $-w = false # Rubyosa gives a load of useless warnings which make debugging difficult

class Jukebox < Plugin
	VolumeFadeStepDelay = 0.05

	def initialize
		super

		@itunes         = OSA.app('iTunes')
		@playlists      = {}
		@playlists_path = @bot.botclass + "/playlists"
		if File.exists?(@playlists_path)
			Dir[@playlists_path + "/*.yaml"].each do |file|
				list = Playlist.load(file)
				@playlists[list.name] = list
			end
		else
			Dir.mkdir(@playlists_path)
		end
		@playlists['choons'] ||= Playlist.new('choons', @playlists_path)
		@randchoon_timer     = nil
	end

	# ===================
	# = Command parsing =
	# ===================
	def listen(rbot)
		case rbot.message

		when /^pause!$/i
			if @itunes.player_state.to_s == 'playing'
				@vol = @itunes.sound_volume
				stop_randchoon_timer
				rbot.reply "Pausing"

				# fade_volume_to(0, rbot)
				@itunes.pause
			end

		when /^play!$/i
			if @itunes.player_state.to_s != 'playing'
				stop_randchoon_timer
				rbot.reply "Playing"

				# @itunes.sound_volume = 0
				@itunes.play
				# fade_volume_to(@vol, rbot)
			end

		when /^album (.+?)$/i
			tracks = []

			album, artist = $1.split(/\s+by\s+/)

			if artist
				tracks = search_tracks(artist, :artists)
				tracks = tracks.select { |t| t.album.downcase.include? album.downcase }
			else
				tracks = search_tracks(album, :albums)
			end

			if tracks.empty?
				rbot.reply "No matching albums"
			else
				stop_randchoon_timer
				track = tracks.select { |t| t.track_number > 0 }.sort { |a, b| a.track_number - b.track_number }.first
				rbot.reply "Playing '#{track.name}' by '#{track.artist}', from '#{track.album}'"
				@itunes.play track
			end

		when /^play (.+)$/i
			name, artist = $1.split(/\s+by\s+/)
			if track = search_and_play(:name => name, :artist => artist)
				rbot.reply "Playing '#{track.name}' by '#{track.artist}'"
			else
				rbot.reply "No matching tracks"
			end

		when /^choons$/
			if track = randchoon
				rbot.reply "Playing '#{track.name}' by '#{track.artist}'"
			else
				rbot.reply "No tracks found"
			end

		when /^unchoon$/
			old_track = @playlists['choons'].delete({ :name => @itunes.current_track.name, :artist => @itunes.current_track.artist })
			randchoon
			rbot.reply "Skipping '#{old_track.name}', playing #{current_track_description}"

		when /(figlet )?c+h+o{2,}n+/i
			rbot.reply "#{'figlet ' if $1}#{current_track_description}"
			@playlists['choons'] << { :name => @itunes.current_track.name, :artist => @itunes.current_track.artist }

		when /^playlist add (\w+)$/i
			@playlists[$1] ||= Playlist.new($1, @playlists_path)
			@playlists[$1] << { :name => @itunes.current_track.name, :artist => @itunes.current_track.artist }
			rbot.reply "#{@itunes.current_track.name} added to playlist '#{$1}'"

		when /^playlist (\w+)$/i
			# TODO playlist playing

		when /^album/i
			track = @itunes.current_track
			if track.compilation?
				rbot.reply "The compilation '#{track.album}'"
			else
				rbot.reply "'#{track.album}' by #{track.artist}"
			end

		when /^(previous|back)!$/i
			stop_randchoon_timer
			@itunes.previous_track
			rbot.reply "Replaying #{current_track_description}"

		when /^again!$/i
			stop_randchoon_timer
			if @itunes.player_state == 'stopped'
				@itunes.previous_track
				@itunes.playpause
			else
				if @itunes.player_position <= 10
					@itunes.previous_track
				else
					# replay current track
					@itunes.player_position = 0
				end
				@itunes.playpause if @itunes.player_state == 'paused'
			end
			rbot.reply "Replaying #{current_track_description}"

		when /^next!$/i
			stop_randchoon_timer
			old_track = @itunes.current_track.name
			@itunes.next_track
			rbot.reply "Skipping '#{old_track}', playing #{current_track_description}"

		when /^\++$/
			fade_volume_to(@itunes.sound_volume + $&.size, rbot)

		when /^-+$/
			fade_volume_to(@itunes.sound_volume - $&.size, rbot)

		when /^Vol(?:ume)?\?$/i
			rbot.reply @itunes.sound_volume

		when /^\+(\d+)$/
			fade_volume_to(@itunes.sound_volume + $1.to_i, rbot)

		when /^\-(\d+)$/
			fade_volume_to(@itunes.sound_volume - $1.to_i, rbot)
		end
	rescue Exception => e
		rbot.reply "Caught exception! #{e} @ #{e.backtrace.shift}"
	end

	# ===================
	# = Utility methods =
	# ===================
	def fade_volume_to(new_vol, rbot)
		old_vol = @itunes.sound_volume
		new_vol = [[new_vol.to_i, 0].max, 100].min
		if old_vol == new_vol
			rbot.reply "Volume is already at #{new_vol == 0 ? 'minimum' : 'maximum'}!"
			return
		end
		if old_vol > new_vol
			old_vol.downto(new_vol) do |v|
				@itunes.sound_volume = v
				sleep VolumeFadeStepDelay
			end
		else
			old_vol.upto(new_vol) do |v|
				@itunes.sound_volume = v
				sleep VolumeFadeStepDelay
			end
		end
		rbot.reply "Volume from #{old_vol} to #{new_vol}"
	end

	def current_track_description
		track = @itunes.current_track
		"'#{track.name}' by #{track.artist} from the #{track.compilation? ? 'compilation' : 'album'} '#{track.album}'"
	end

	def search_and_play(query)
		tracks = []

		if query[:artist]
			tracks = search_tracks(query[:artist], :artist)
			tracks = tracks.select { |t| t.name.downcase.include? query[:name].downcase }
		else
			tracks = search_tracks(query[:name])
		end
		if tracks.empty?
			nil
		else
			stop_randchoon_timer
			track = tracks.first
			@itunes.play track
			track
		end
	end

	def randchoon
		choon = @playlists['choons'][rand(@playlists['choons'].track_count)]
		if choon and choon = search_and_play(choon)
			# We allow for a second of latency in playing the track
			@randchoon_timer = @bot.timer.add(choon.duration - 1) { randchoon }
			choon
		else
			false
		end
	end

	def stop_randchoon_timer
		@bot.timer.remove(@randchoon_timer) if @randchoon_timer
		@randchoon_timer = nil
	end

	def search_tracks(query, where = :all)
		case where
		when :artist
			where = OSA::ITunes::ESRA::ARTISTS
		when :song
			where = OSA::ITunes::ESRA::SONGS
		when :albums
			where = OSA::ITunes::ESRA::ALBUMS
		else
			where = OSA::ITunes::ESRA::ALL
		end

		matches = []

		libraries = []
		@itunes.sources.each do |source|
			libraries += source.library_playlists.to_a
		end

		libraries.each do |library|
			library.search(query, where).each do |track|
				matches << track
			end
		end
		matches
	end
end

plugin = Jukebox.new
plugin.register("jukebox")
