class Playlist
  def initialize(name, path)
    @name   = name
    @tracks = []
    @file   = nil
    @path   = path
  end
  attr_reader :name

  def file
    unless @file
      @file = @path + "/" + @name + ".yaml"
    end
    @file
  end
  attr_writer :file

  def self.load(file)
    instance = nil
    if File.exists?(file)
      instance      = YAML.load(File.read(file))
      instance.file = file
    end
    instance
  end

  def <<(value)
    @tracks << value
    save
  end
  def []=(key, value)
    @tracks[key] = value
    save
  end
  def [](key)
    @tracks[key]
  end
  def delete( value )
    @tracks.delete(value)
    save
  end
  def track_count
    @tracks.size
  end

  protected
  def save
    File.open(file, "w") do |f|
      YAML.dump(self, f)
    end
  end
end
