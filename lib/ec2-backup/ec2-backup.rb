require 'active_support/all'
require 'fog'

class Ec2Backup
  def initialize

    @settings = YAML.load_file("#{ENV['HOME']}/.ec2-backup.yml")

    @hourly_snapshots  = @settings['hourly_snapshots']
    @daily_snapshots   = @settings['daily_snapshots']
    @weekly_snapshots  = @settings['weekly_snapshots']
    @monthly_snapshots = @settings['monthly_snapshots']
    @tags              = @settings['tags']

  end

  ###############################################################################
  # def log
  #
  # Purpose: Neatly logs events to the screen
  # Parameters:
  #   text<~String>: The text to log to the screen
  # Returns:
  #   <~String> - Full line of text
  ###############################################################################
  def log(text)
    puts "[#{Time.now}] \e[0;30mCaller: #{caller[0][/`(.*)'/,1]} \e[0m| #{text}"
  end

  ###############################################################################
  # def ec2
  #
  # Purpose: Connects to the Amazon API
  # Parameters: None
  # Returns: Fog::Compute::AWS
  ###############################################################################
  def ec2
    Fog::Compute::AWS.new(aws_access_key_id: @aws_access_key_id, aws_secret_access_key: @aws_secret_access_key)
  end

  ###############################################################################
  # def volume_snapshots
  #
  # Purpose: Returns all snapshots associated with an EBS volume id
  # Parameters:
  #   volume_id<~String>: The volume id of the EBS volume
  # Returns: <~Array>
  #           Fog::AWS::Snapshot
  ###############################################################################
  def volume_snapshots(volume_id)
    ec2.snapshots.select { |snapshot| snapshot.volume_id == volume_id }
  end

  ###############################################################################
  # def find_instances
  #
  # Purpose: Returns all servers with matching key-value tags
  # Parameters:
  #   tags<~Hash>: key-value pairs of tags to match against EC2 instances
  # Returns: <~Array>
  #           Fog::Compute::AWS::Server
  #
  ###############################################################################
  def find_instances(tags)
    attempts = 0
    begin
      ec2.servers.select { |server| tags.reject { |k,v| server.tags[k] == tags[k] }.empty? }
    rescue Excon::Errors::ServiceUnavailable
      sleep 5
      attempts += 1
      return [] if attempts == 5
      retry
    end
  end

  ###############################################################################
  # def create_snapshot
  #
  # Purpose: Creates an EBS snapshot
  # Parameters:
  #   options<~Hash>
  #     volume_id<~String>: The volume id to snapshot
  #     description<~String>: The description of the snapshot
  #     snapshot_type<~String>: The type of snapshot being created (hourly, etc)
  #     tags<~Hash>: Key-value pairs of tags to apply to the snapshot
  # Returns: nil
  ###############################################################################
  def create_snapshot(options)
    snapshot = ec2.snapshots.new
    snapshot.volume_id = options['volume_id']
    snapshot.description = options['description']

    attempts = 0

    begin
      snapshot.save
      snapshot.reload
    rescue Fog::Compute::AWS::Error
      sleep 5
      attempts += 1
      if attempts == 5
        log "Error communicating with API; Unable to save volume `#{options['volume_id']}` (Desc: #{options['description']})"
      end
      return unless attempts == 5
    end

    options['tags'].each do |k,v|
      begin
        ec2.tags.create({resource_id: snapshot.id, key: k, value: v})
      rescue Errno::EINPROGRESS , Errno::EISCONN
        log "API Connection Error"
        sleep 1
        retry
      rescue Fog::Compute::AWS::Error
        log "Failed attaching tag `'#{k}' => #{v}` to #{options['snapshot_type']} snapshot #{snapshot.id}"
        sleep 1
        retry
      end
    end

  end

  ###############################################################################
  # def delete_snapshot
  #
  # Purpose: Delete an EBS snapshot from Amazon EC2
  # Parameters:
  #   snapshot_id<~String>: The id of the snapshot to be deleted
  # Returns: nil
  ###############################################################################
  def delete_snapshot(snapshot_id)
    log "\e[0;31m:: Deleting snapshot:\e[0m #{snapshot_id}"

    begin
      ec2.delete_snapshot(snapshot_id)
      sleep 0.2
    rescue Fog::Compute::AWS::NotFound
      log "Failed to delete snapshot: #{snapshot_id}; setting { 'protected' => true }"
      ec2.tags.create({resource_id: snapshot_id, key: 'protected', value: 'true'})
    rescue Fog::Compute::AWS::Error
      log "API Error"
    end

  end

  ###############################################################################
  # def too_soon?
  #
  # Purpose: Determines if enough time has passed between taking snapshots
  # Parameters:
  #   history<~Array>
  #     Fog::Compute::AWS::Snapshot: Volume snapshot
  #   snapshot_type<~String>: The type of snapshot (hourly, etc)
  # Returns: Boolean
  ###############################################################################
  def too_soon?(history,snapshot_type)

    # If the backup history size is zero,
    # the server doesn't have any backups yet.
    return false if history.size == 0

    elapsed = Time.now - history.last.created_at

    case snapshot_type
    when 'hourly'
      elapsed < 1.hour
    when 'daily'
      elapsed < 1.day
    when 'weekly'
      elapsed < 1.week
    when 'monthly'
      elapsed < 1.month
    end

  end

  ###############################################################################
  # def start
  #
  # Purpose: Start the backup process
  # Parameters: none
  # Returns: nil
  ###############################################################################
  def start

    @settings['accounts'].each do |account,keys|

      puts "Account: #{account}"
      @aws_access_key_id     = keys['access_key_id']
      @aws_secret_access_key = keys['secret_access_key']

      # Find all servers with tags matching the supplied Hash
      find_instances(@tags).each do |server|

        # Begin snapshotting each volume attached to the server
        #
        server.block_device_mapping.each do |block_device|

          log "\e[0;32m Searching for matching snapshots \e[0m(#{server.id}:#{block_device}).."
          snapshots = volume_snapshots(block_device['volumeId'])

          # Create each type of backup we'll be using
          #
          %w(hourly daily weekly monthly).each do |snapshot_type|

            # Build snapshot history for the working volume and return all snapshots
            # matching our particular snapshot type
            history = snapshots.select do |snapshot|
              snapshot.tags['snapshot_type'] == snapshot_type  &&
                snapshot.tags['volume_id'] == block_device['volumeId'] &&
                snapshot.tags['protected'] == 'false'
            end

            history.sort_by! { |snapshot| snapshot.created_at }

            unless too_soon?(history,snapshot_type)

              # Check against threshold limits for backup history and delete as needed
              #
              while history.size >= instance_variable_get("@#{snapshot_type}_snapshots")
                delete_snapshot(history.first.id)
                history.delete(history.first)
              end

              log "Creating #{snapshot_type} for #{block_device['volumeId']}.."
              create_snapshot({
                'volume_id'     => block_device['volumeId'],
                'snapshot_type' => snapshot_type,
                'description'   => "Snapshot::#{snapshot_type.capitalize}> Server: #{server.id}",
                'tags'          => {
                  'snapshot_time' => "#{Time.now}",
                  'snapshot_type' => snapshot_type,
                  'instance_id'   => server.id,
                  'volume_id'     => block_device['volumeId'],
                  'deviceName'    => block_device['deviceName'],
                  'protected'     => 'false'
                }
              })
            end
          end
        end
      end
    end

  end
end
