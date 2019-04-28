# Device Helper
# It provides helper functions related to devices,blocks,filesystems and nitro instance handling in ec2.
module Device
  module Helper
    require 'mixlib/shellout'
    require 'json'
    #####################################################################################################
    # Device Functions
    #####################################################################################################
    def device_exists?(device) # Check if the mount device is value is valid.
      # Check if OHAI has detect it. There chances that PCI scan is not complete when OHAI is running.
      return true if node['filesystem']['by_device'].keys.include?(device)
      # The sym link is present to the device.udev rule maps it properly in nitro instances
      return true if ::File.symlink?(device) && node['filesystem']['by_device'].keys.include?(get_device_mapping(device))
      Chef::Log.error("#{device} doesn't exist or is not detected yet.")
      false
    end

    def device_mounted?(device) # If Device is already mounted
      # We are doing the mount in chef so we it will be detected by ohai.
      source_device = get_device_mapping(device) # Getting the symlink if the instance is nitro
      device_details = node['filesystem']['by_device'][source_device]
      # Device doesn't exist.
      return false if device_details.nil?
      !(device_details['mounts'].nil? || device_details['mounts'].empty?)
    end

    def device_is_root?(device) # If mount device is root device
      node['filesystem']['by_mountpoint']['/']['devices'].include?(device)
    end

    def fetch_root_device # Get the root device
      node['filesystem']['by_mountpoint']['/']['devices'].select { |device| device.start_with?('/dev/') }.first
    end
    #####################################################################################################

    #####################################################################################################
    # Mount and File System Functions
    #####################################################################################################
    def device_filesystem_created?(given_source_device) # If Device file system is already created
      source_device = get_device_mapping(given_source_device)
      device_details = node['filesystem']['by_device'][source_device]
      return false if device_details.nil?
      !device_details['fs_type'].nil?
    end

    def mountable?(source_dir, given_source_device)
      source_device = get_device_mapping(given_source_device)
      # Is not mountable if The source dir is already mounted.
      return false if Pathname.new(source_dir).mountpoint?

      # Is not mountable If device doesn't exists. you really can't mount something not detect.
      # I would love you try it. It is like building castles in sky
      return false if device_exists?(source_device) == false

      # Is not mountable If Device is root device.
      return false if given_source_device == 'auto' || device_is_root?(source_device)

      # Is not mountable If device is already mounted.
      return false if device_mounted?(source_device)

      # Otherwise It is mountable
      true
    end

    def filesystem_createable?(given_source_device)
      source_device = get_device_mapping(given_source_device)
      # Is not createable If The source device is autodetected.It is root device
      return false if given_source_device == 'auto' || device_is_root?(source_device)

      # Is not createable If device doesn't exists
      return false if device_exists?(source_device) == false

      # Is not createable If file system is already created.
      return false if device_filesystem_created?(source_device)

      # Otherwise It is createable
      true
    end
    #####################################################################################################

    #####################################################################################################
    # Ec2 Instance : Nitro Block Mapping
    #####################################################################################################
    def nitro_instance?
      return false if node['ec2'].nil? # Not a EC2 Instance so not a nitro instance
      # Checking if it is a nitro instance using all all nitro instance family
      %w( a1 c5 c5d c5n m5 m5a m5ad m5d p3dn.24xlarge r5 r5a r5ad r5d t3 t3a z1d).each do |type|
        return true if node['ec2']['instance_type'].downcase.include?(type)
      end
      Chef::Log.error('Instance is not a nitro type.Please consider using nitro')
      false
    end

    # Device mapping function returns the root device when auto is given
    # it detects whether instance is nitro, then it uses symlink
    # Otherwise just returns the device.
    def get_device_mapping(source_device) # Used to get mapping if the device is a nitro device.
      return fetch_root_device if source_device == 'auto' # Returning root device if auto is given.
      if  nitro_instance? && ::File.symlink?(source_device)
        link = ::File.readlink(source_device)
        return link if link.start_with?('/dev/')
        return "/dev/#{link}"
      end
      source_device
    end
    #####################################################################################################
  end
end
