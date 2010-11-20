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
  myspace_page = URI.parse("http://www.myspace.com/#{artist}").read

  # Find necessary params in screenscrape of artist page
  regex = Regexp.new(/reportedUserId=(\d+)/m)
  matchdata = regex.match(myspace_page)
  profile_id = matchdata[1]

  myspace_page2 = URI.parse("http://www.myspace.com/#{profile_id}/classic").read
  regex2 = Regexp.new(/plid=(\d+)&profid=(\d+)&ptype=(\d+)&artid=(\d+)/m)
  matchdata2 = regex2.match(myspace_page2)
  playlist_id = matchdata2[1]
  
  # Retreive XML playlist
  playlist_url = "http://musicservices.myspace.com/Modules/MusicServices/Services/MusicPlayerService.ashx?action=getPlaylist&friendId=#{profile_id}&playlistId=#{playlist_id}"
  xml_data = URI.parse(playlist_url).read
  data = XmlSimple.xml_in(xml_data)
  tracks = []
  data['trackList'][0]['track'].each do |_track|
    # Make Track Object
    track = Track.new
    track.title = _track['title']
    track.duration = Time.at( Integer(_track['duration'][0]) ).gmtime.strftime('%M:%S')
    track.id = _track['song'][0]['songId']
    tracks << track
  end
  
  return tracks
end

def getTracks(tracks, uuid)

  temp_path = "tracks/temp/"  
  archive_path = "tracks/archives/"
  archive_name = uuid
  
  tracks.each do |t|
    track_id = t[0]
  
    track_url = "http://musicservices.myspace.com/Modules/MusicServices/Services/MusicPlayerService.ashx?action=getSong&ptype=3&sample=0&songId=#{track_id}"
    xml_data = URI.parse(track_url).read
    data = XmlSimple.xml_in(xml_data)
    url = data['trackList'][0]['track'][0]['rtmp']
    title = data['trackList'][0]['track'][0]['title']
    temp_filename = UUIDTools::UUID.timestamp_create
    filename = "#{title}.mp3"
    %x[mkdir -p #{archive_path}#{archive_name} && rtmpdump -r "#{url}" -o "#{temp_path}#{temp_filename}" -W http://lads.myspacecdn.com/videos/MSMusicPlayer.swf && ffmpeg -i "#{temp_path}#{temp_filename}" -sameq "#{archive_path}#{archive_name}/#{filename}" && rm "#{temp_path}#{temp_filename}" ]
    # NEXT FEATURE... Add id3 tags to each track
    # Mp3Info.open(filename) do |mp3|
    #   mp3.tag.title = title
    #   mp3.tag.artist = artist
    #   mp3.artwork etc.etc.
    # end
  end
  
  %x[cd "#{archive_path}" && tar cvzf "#{archive_name}.tar.gz" "#{archive_name}" && rm -rf "#{archive_name}"]
  
  return "#{archive_path}#{archive_name}.tar.gz"

end

helpers do

  def protected!
    unless authorized?
      response['WWW-Authenticate'] = %(Basic realm="Testing")
      throw(:halt, [401, "Not authorized\n"])
    end
  end

  def authorized?
    @auth ||=  Rack::Auth::Basic::Request.new(request.env)
    @auth.provided? && @auth.basic? && @auth.credentials && @auth.credentials == ['myspace', 'isshit']
  end

end

get '/' do
  protected!
  haml :search
end

post '/artist' do
  protected!
  artist = params[:artist].split('/').pop
  @tracks = getTracklist(artist)
  haml :tracks
end

get '/wait/:uuid' do
  protected!
  if FileTest.exists?("tracks/archives/#{params[:uuid]}.tar.gz")
    @archive = "tracks/archives/#{params[:uuid]}.tar.gz"
  end
  haml :wait
end

get '/download/:uuid' do
  protected!
  file = "tracks/archives/#{params[:uuid]}.tar.gz"
end

post '/track' do
  protected!
  uuid = UUIDTools::UUID.timestamp_create
  file = getTracks(params[:tracks],uuid)
  send_file(file, :disposition => 'attachment', :filename => File.basename(file))
end