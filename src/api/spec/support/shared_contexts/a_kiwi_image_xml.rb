RSpec.shared_context 'a kiwi image xml' do
  let(:kiwi_xml) do
    <<-XML.strip_heredoc
      <?xml version="1.0" encoding="UTF-8"?>
      <!-- OBS-Profiles: profile1 profile2 inexistent -->
      <image name="Christians_openSUSE_13.2_JeOS" displayname="Christians_openSUSE_13.2_JeOS" schemaversion="5.2">
        <description type="system">
          <author>Christian Bruckmayer</author>
          <contact>noemail@example.com</contact>
          <specification>Tiny, minimalistic appliances</specification>
        </description>
        <profiles>
            <profile name="profile1" description="My first profile" arch="x86_64"/>
            <profile name="profile2" description="My second profile" arch="i586"/>
            <profile name="profile3" description="My third profile" arch="x86_64"/>
        </profiles>
        <preferences>
          <type image="docker" boot="grub">
            <containerconfig
              name="my_container"
              tag="latest" />
              <oemconfig>test</oemconfig>
          </type>
          <bootsplash-theme>gnome</bootsplash-theme>
          <bootloader-theme>gnome-dark</bootloader-theme>
          <version>2.0.0</version>
        </preferences>
        <packages type="image" patternType="onlyRequired">
          <package name="e2fsprogs"/>
          <package name="aaa_base"/>
          <package name="branding-openSUSE"/>
          <package name="patterns-openSUSE-base"/>
          <package name="grub2"/>
          <package name="hwinfo"/>
          <package name="iputils"/>
          <package name="kernel-default"/>
          <package name="netcfg"/>
          <package name="openSUSE-build-key"/>
          <package name="openssh"/>
          <package name="plymouth"/>
          <package name="polkit-default-privs"/>
          <package name="rpcbind"/>
          <package name="syslog-ng"/>
          <package name="vim"/>
          <package name="zypper"/>
          <package name="timezone"/>
          <package name="openSUSE-release-dvd"/>
          <package name="gfxboot-devel" bootinclude="true"/>
        </packages>
        <packages type="delete">
          <package name="e2fsprogss"/>
        </packages>
        <repository type="apt-deb" priority="10" alias="debian" imageinclude="true" password="123456" prefer-license="true" status="replaceable" username="Tom">
          <source path="http://download.opensuse.org/update/13.2/"/>
        </repository>
        <repository type="rpm-dir" priority="20" imageinclude="false" prefer-license="false">
          <source path="http://download.opensuse.org/distribution/13.2/repo/oss/"/>
        </repository>
        <repository type="yast2" priority="20">
          <source path="http://download.opensuse.org/distribution/13.1/repo/oss/"/>
        </repository>
        <repository type="rpm-md">
          <source path="http://download.opensuse.org/distribution/12.1/repo/oss/"/>
        </repository>
      </image>
    XML
  end

  let(:kiwi_xml_with_obsrepositories) do
    <<-XML.strip_heredoc
      <?xml version="1.0" encoding="UTF-8"?>
      <image name="Christians_openSUSE_13.2_JeOS" displayname="Christians_openSUSE_13.2_JeOS" schemaversion="5.2">
        <description type="system">
          <author>Christian Bruckmayer</author>
          <contact>noemail@example.com</contact>
          <specification>Tiny, minimalistic appliances</specification>
        </description>
        <packages type="image" patternType="onlyRequired">
          <package name="e2fsprogs"/>
          <package name="aaa_base"/>
          <package name="branding-openSUSE"/>
          <package name="patterns-openSUSE-base"/>
          <package name="grub2"/>
          <package name="hwinfo"/>
          <package name="iputils"/>
          <package name="kernel-default"/>
          <package name="netcfg"/>
          <package name="openSUSE-build-key"/>
          <package name="openssh"/>
          <package name="plymouth"/>
          <package name="polkit-default-privs"/>
          <package name="rpcbind"/>
          <package name="syslog-ng"/>
          <package name="vim"/>
          <package name="zypper"/>
          <package name="timezone"/>
          <package name="openSUSE-release-dvd"/>
          <package name="gfxboot-devel" bootinclude="true"/>
        </packages>
        <packages type="delete">
          <package name="e2fsprogss"/>
          <package name="bbb_base"/>
        </packages>
        <repository type="rpm-md">
          <source path="obsrepositories:/"/>
        </repository>
        <preferences>
          <type image="docker" boot="grub"/>
          <version>2.0.0</version>
        </preferences>
      </image>
    XML
  end

  let(:kiwi_xml_with_multiple_descriptions) do
    <<-XML.strip_heredoc
      <?xml version="1.0" encoding="UTF-8"?>
      <image name="Christians_openSUSE_13.2_JeOS" displayname="Christians_openSUSE_13.2_JeOS" schemaversion="5.2">
        <description type="system">
          <author>Christian Bruckmayer</author>
          <contact>noemail@example.com</contact>
          <specification>Tiny, minimalistic appliances</specification>
        </description>
        <description type="boot">
          <author>The KIWI Team</author>
          <contact>kiwi@example.com</contact>
          <specification>Kiwi, tiny, minimalistic appliances</specification>
        </description>
        <preferences>
          <type image="docker" boot="grub"/>
          <version>2.0.0</version>
        </preferences>
      </image>
    XML
  end
end
