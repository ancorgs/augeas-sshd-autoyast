sshd_section = <<EOF
<sshd>
  <config>
    <AcceptEnv config:type="list">
      <listentry>LANG LC_CTYPE LC_NUMERIC LC_TIME LC_COLLATE LC_MONETARY LC_MESSAGES</listentry> 
      <listentry>LC_PAPER LC_NAME LC_ADDRESS LC_TELEPHONE LC_MEASUREMENT</listentry> 
      <listentry>LC_IDENTIFICATION LC_ALL</listentry> 
    </AcceptEnv>
    <AllowTcpForwarding config:type="list">
      <listentry>yes</listentry> 
    </AllowTcpForwarding>
    <Banner config:type="list">
      <listentry>/etc/issue</listentry> 
    </Banner>
    <Compression config:type="list">
      <listentry>yes</listentry> 
    </Compression>
    <MaxAuthTries config:type="list">
      <listentry>6</listentry> 
    </MaxAuthTries>
    <PasswordAuthentication config:type="list">
      <listentry>yes</listentry> 
    </PasswordAuthentication>
    <PermitRootLogin config:type="list">
      <listentry>no</listentry> 
    </PermitRootLogin>
    <PermitUserEnvironment config:type="list">
      <listentry>yes</listentry> 
    </PermitUserEnvironment>
    <PrintMotd config:type="list">
      <listentry>yes</listentry> 
    </PrintMotd>
    <Protocol config:type="list">
      <listentry>2</listentry> 
    </Protocol>
    <PubkeyAuthentication config:type="list">
      <listentry>yes</listentry> 
    </PubkeyAuthentication>
    <RSAAuthentication config:type="list">
      <listentry>yes</listentry> 
    </RSAAuthentication>
    <Subsystem config:type="list">
      <listentry>sftp /usr/lib64/ssh/sftp-server</listentry> 
    </Subsystem>
    <UsePAM config:type="list">
      <listentry>yes</listentry> 
    </UsePAM>
    <X11Forwarding config:type="list">
      <listentry>yes</listentry> 
    </X11Forwarding>
  </config>
  <status config:type="boolean">true</status> 
</sshd>
EOF

require "rexml/document"
require "augeas"
SSHD = "/etc/ssh/sshd_config"

# Quick hack, it should be possible to configure REXML to accept (or ignore)
# the config namespace for attributes
sshd_section.gsub!("config:", "")
xml = REXML::Document.new sshd_section

# Prevent Augeas from loading all known files in the system, we only
# care about sshd_config
Augeas::open(nil, nil, Augeas::NO_MODL_AUTOLOAD) do |augeas|
  augeas.transform(
    :lens => "Sshd.lns",
    :incl => SSHD
  )
  augeas.load

  xml.elements.each("sshd/config/*") do |param|
    root = "/files/#{SSHD}/#{param.name}"
    # Position matters, we don't want our script to add stuff at the end.
    # So search for the first occurrence in the file
    if augeas.exists(root)
      # Add a new node to store our values and wipe out all previous values
      before = true
      augeas.insert(root, param.name, before)
      augeas.rm("#{root}[position() > 1]")
    else
      # Let's try at least to find the commented version. If not, it will be
      # inserted at the end of the tree
      comment = "/files/#{SSHD}/#comment[. =~ regexp('#{param.name} .*')]"
      before = false
      augeas.insert(comment, param.name, before)
    end

    # The same parameter can appear several times in the xml and in sshd_config
    param.elements.each_with_index("listentry") do |entry, idx|
      if idx > 0
        before = false
        augeas.insert("#{root}[#{idx}]", param.name, before)
      end
      new_node = "#{root}[#{idx+1}]"
      case param.name
      when "AcceptEnv"
        # AcceptEnv needs to be broken down into pieces
        entry.text.split.each_with_index do |var, vidx|
          augeas.set("#{new_node}/#{vidx+1}", var)
        end
      when "Subsystem"
        # Each subsystem is a branch in the Augeas tree
        entry.text.split.each_slice(2) do |sys|
          augeas.set("#{new_node}/#{sys.first}", sys.last)
        end
      else
        # Default case, just write every value of the param
        augeas.set(new_node, entry.text)
      end
    end
  end

  if augeas.save
    puts "sshd_config: saved with no errors"
  else
    puts "sshd_config: not touched or only partially written"
  end
end
