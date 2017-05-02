require 'spec_helper'

describe Bosh::OpenStackCloud::Cloud do

  let(:server_metadata) do
    [
      double('metadatum', :key => 'lbaas_pool_0', :value => 'pool-id-0/membership-id-0'),
      double('metadatum', :key => 'job', :value => 'bosh')
    ]
  end

  let(:server) { double('server', :id => 'i-foobar', :name => 'i-foobar', :metadata => server_metadata) }
  let(:cloud) do
    mock_cloud do |fog|
      allow(fog.compute.servers).to receive(:get).with('i-foobar').and_return(server)
    end
  end
  before(:each) do
     @registry = mock_registry

     allow(Bosh::OpenStackCloud::NetworkConfigurator).to receive(:port_ids).and_return(['port_id'])
     allow(Bosh::OpenStackCloud::NetworkConfigurator).to receive(:cleanup_ports)
     allow(server).to receive(:destroy)
     allow(cloud.openstack).to receive(:wait_resource)
     allow(@registry).to receive(:delete_settings)
     allow(Bosh::OpenStackCloud::LoadbalancerConfigurator).to receive(:cleanup_memberships)
   end

  context 'when server retrieval fails' do
    let(:cloud) do
      mock_cloud do |fog|
        allow(fog.compute.servers).to receive(:get).with('i-foobar').and_raise('BOOM!')
      end
    end

    it 'stops and raises' do
      expect{
        cloud.delete_vm('i-foobar')
      }.to raise_error('BOOM!')
    end
  end

  context 'when server cannot be found' do
    let(:cloud) do
      mock_cloud do |fog|
        allow(fog.compute.servers).to receive(:get).with('i-foobar').and_return(nil)
      end
    end

    before(:each) do
      allow(Bosh::Clouds::Config.logger).to receive(:info)
    end

    it 'stops and logs' do
      cloud.delete_vm('i-foobar')

      expect(Bosh::Clouds::Config.logger).to have_received(:info).with('Server `i-foobar\' not found. Skipping.')
    end
  end

  it 'deletes an OpenStack server' do
    cloud.delete_vm('i-foobar')

    expect(server).to have_received(:destroy)
    expect(cloud.openstack).to have_received(:wait_resource).with(server, [:terminated, :deleted], :state, true)
    expect(Bosh::OpenStackCloud::NetworkConfigurator).to have_received(:cleanup_ports).with(any_args, ['port_id'])
    expect(@registry).to have_received(:delete_settings).with('i-foobar')
    expect(Bosh::OpenStackCloud::LoadbalancerConfigurator).to have_received(:cleanup_memberships).with(
      {
        'lbaas_pool_0' => 'pool-id-0/membership-id-0',
        'job' => 'bosh'
      }
    )
  end

  context 'when server destroy fails' do
    it 'stops and raises' do
      allow(server).to receive(:destroy).and_raise('BOOM!')

      expect{
        cloud.delete_vm('i-foobar')
      }.to raise_error('BOOM!')
    end
  end

  context 'when getting ports fails' do
    it 'stops and raises' do
      allow(Bosh::OpenStackCloud::NetworkConfigurator).to receive(:port_ids).and_raise('BOOM!')

      expect{
        cloud.delete_vm('i-foobar')
      }.to raise_error('BOOM!')
    end
  end

  context 'when port cleanup fails' do
    it 'does everything else but fails in the end' do
      allow(Bosh::OpenStackCloud::NetworkConfigurator).to receive(:cleanup_ports).and_raise('BOOM!')

      expect {
        cloud.delete_vm('i-foobar')
      }.to raise_error('BOOM!')

      expect(@registry).to have_received(:delete_settings).with('i-foobar')
      expect(Bosh::OpenStackCloud::LoadbalancerConfigurator).to have_received(:cleanup_memberships).with(
        {
          'lbaas_pool_0' => 'pool-id-0/membership-id-0',
          'job' => 'bosh'
        }
      )
    end
  end

  context 'when destruction of LBaaS membership fails' do
    it 'does everything else and fails' do
      allow(Bosh::OpenStackCloud::LoadbalancerConfigurator).to receive(:cleanup_memberships).and_raise('BOOM!')

      expect{
        cloud.delete_vm('i-foobar')
      }.to raise_error('BOOM!')


      expect(Bosh::OpenStackCloud::NetworkConfigurator).to have_received(:cleanup_ports).with(any_args, ['port_id'])
      expect(@registry).to have_received(:delete_settings).with('i-foobar')
    end
  end


  context 'when port cleanup and LBaaS membership cleanup fails' do
    it 'fails with both errors, but deletes the registry settings' do
      allow(Bosh::OpenStackCloud::NetworkConfigurator).to receive(:cleanup_ports).and_raise('BOOM!')
      allow(Bosh::OpenStackCloud::LoadbalancerConfigurator).to receive(:cleanup_memberships).and_raise('BOOM!')

      expect{
        cloud.delete_vm('i-foobar')
      }.to raise_error(Bosh::Clouds::CloudError, "Multiple Cloud Errors occurred:\nBOOM!\nBOOM!")

      expect(Bosh::OpenStackCloud::NetworkConfigurator).to have_received(:cleanup_ports).with(any_args, ['port_id'])
      expect(Bosh::OpenStackCloud::LoadbalancerConfigurator).to have_received(:cleanup_memberships).with(
        {
          'lbaas_pool_0' => 'pool-id-0/membership-id-0',
          'job' => 'bosh'
        }
      )
      expect(@registry).to have_received(:delete_settings).with('i-foobar')
    end
  end
end
