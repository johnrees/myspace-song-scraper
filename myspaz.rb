#!/usr/bin/ruby

require 'sinatra'
require 'open-uri'
require 'xmlsimple'
require 'haml'
require 'uuidtools'
# require 'mp3info'

class Track
  attr_accessor :title, :duration, :id
end


def getTracklist(artist)
  # Parse the artist's Myspace Profile
  myspace_page = URI.parse("http://www.myspace.com/#{artist}").read

  # Use Regex to retreive the Artist's Myspace ID
  regex = Regexp.new(/reportedUserId=(\d+)/m)
  matchdata = regex.match(myspace_page)
  profile_id = matchdata[1]

  # As the profile has now changed you must now parse the *classic* profile
  myspace_page2 = URI.parse("http://www.myspace.com/#{profile_id}/classic").read
  regex2 = Regexp.new(/plid=(\d+)&profid=(\d+)&ptype=(\d+)&artid=(\d+)/m)
  matchdata2 = regex2.match(myspace_page2)
  playlist_id = matchdata2[1]
  
  # Retreive XML playlist
  playlist_url = "http://musicservices.myspace.com/Modules/MusicServices/Services/MusicPlayerService.ashx?action=getPlaylist&friendId=#{profile_id}&playlistId=#{playlist_id}"
  xml_data = URI.parse(playlist_url).read
  data = XmlSimple.xml_in(xml_data)
  tracks = []
  
  # Iterate each track in the XML
  data['trackList'][0]['track'].each do |_track|
    # Initialise new Track
    track = Track.new
    track.title = _track['title']
    # Convert s into Minutes:Seconds format for readability
    track.duration = Time.at( Integer(_track['duration'][0]) ).gmtime.strftime('%M:%S')
    track.id = _track['song'][0]['songId']
    tracks << track
  end
  
  # Return a lit of tracks
  return tracks
end


def getTracks(tracks, uuid)
  
  # Set local paths to storage dirs
  temp_path = "tracks/temp/"  
  archive_path = "tracks/archives/"
  
  # Use the Unique ID for the archive name
  archive_name = uuid
  
  tracks.each do |t|
    track_id = t[0]
    # Parse XML file containing link to RTMP stream for the current track
    track_url = "http://musicservices.myspace.com/Modules/MusicServices/Services/MusicPlayerService.ashx?action=getSong&ptype=3&sample=0&songId=#{track_id}"
    xml_data = URI.parse(track_url).read
    data = XmlSimple.xml_in(xml_data)
    url = data['trackList'][0]['track'][0]['rtmp']
    title = data['trackList'][0]['track'][0]['title']
    temp_filename = UUIDTools::UUID.timestamp_create
    filename = "#{title}.mp3"
    # Create a folder for the tracks, collect the RTMP Streams
    %x[mkdir -p #{archive_path}#{archive_name} && rtmpdump -r "#{url}" -o "#{temp_path}#{temp_filename}" -W http://lads.myspacecdn.com/videos/MSMusicPlayer.swf]
    # Convert the scrambled FLVs into MP3s of the same bitrate then remove the original FLV
    %x[ffmpeg -i "#{temp_path}#{temp_filename}" -sameq "#{archive_path}#{archive_name}/#{filename}" && rm "#{temp_path}#{temp_filename}" ]
    
    # NEXT FEATURE... Add id3 tags to each track
    # Mp3Info.open(filename) do |mp3|
    #   mp3.tag.title = title
    #   mp3.tag.artist = artist
    #   mp3.artwork etc.etc.
    # end
  end
  
  # Archive the downloads folder and remove the original
  %x[cd "#{archive_path}" && tar cvzf "#{archive_name}.tar.gz" "#{archive_name}" && rm -rf "#{archive_name}"]
  
  # Return the archive's path as a string for download
  return "#{archive_path}#{archive_name}.tar.gz"

end

# Authorisation
# Change the HARDCODED values below
helpers do

  def protected!
    unless authorized?
      response['WWW-Authenticate'] = %(Basic realm="Please Authenticate Yourself")
      throw(:halt, [401, "Not authorized\n"])
    end
  end

  def authorized?
    @auth ||=  Rack::Auth::Basic::Request.new(request.env)
    @auth.provided? && @auth.basic? && @auth.credentials && @auth.credentials == ['HARDCODEDUSERNAME', 'HARDCODEDPASSWORD']
  end

end

# Sinatra's Magic
# TODO: Convert this to a Sinatra::Base Class

# Homepage, show search box
get '/' do
  protected!
  haml :search
end

# List Artist's Tracks
post '/artist' do
  protected!
  artist = params[:artist].split('/').pop
  @tracks = getTracklist(artist)
  haml :tracks
end

# Waiting page (for non-concurrent processing)
get '/wait/:uuid' do
  protected!
  if FileTest.exists?("tracks/archives/#{params[:uuid]}.tar.gz")
    @archive = "tracks/archives/#{params[:uuid]}.tar.gz"
  end
  haml :wait
end

# Download page
get '/download/:uuid' do
  protected!
  file = "tracks/archives/#{params[:uuid]}.tar.gz"
end

# Download process, return selected track as a file attachment (forced-download)
post '/track' do
  protected!
  uuid = UUIDTools::UUID.timestamp_create
  file = getTracks(params[:tracks],uuid)
  send_file(file, :disposition => 'attachment', :filename => File.basename(file))
end