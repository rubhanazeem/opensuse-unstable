require 'rails_helper'

RSpec.describe AttribValue, type: :model do
  let(:attrib) { create(:attrib_with_default_value) }
  let(:user) { create(:confirmed_user) }

  before do
    login user
  end

  describe 'callbacks' do
    context 'set defaults' do
      let!(:attrib_value) { create(:attrib_value, attrib: attrib) }

      it 'adds new elements on top' do
        expect(create(:attrib_value, attrib: attrib)).to be_first
        expect(attrib_value.reload).to be_last
      end

      it 'adds new elements to assigned position' do
        expect(create(:attrib_value, attrib: attrib, position: 2)).to be_last
        expect(attrib_value.reload).to be_first
      end
    end
  end

  describe '#to_s' do
    context 'without setting a value' do
      let(:attrib_value) { create(:attrib_value, attrib: attrib) }
      let(:default_value) { attrib.attrib_type.default_values.first.value }

      it 'returns the default value' do
        expect(attrib_value.to_s).to eq(default_value)
      end
    end

    context 'with a value' do
      let(:attrib_value) { create(:attrib_value, attrib: attrib, value: 'value that is set') }

      it 'returns the value which is set' do
        expect(attrib_value.to_s).to eq('value that is set')
      end
    end

    context 'with an empty value' do
      let(:attrib_value) { create(:attrib_value, attrib: attrib, value: '') }
      let(:default_value) { attrib.attrib_type.default_values.first.value }

      it 'returns the default value' do
        expect(attrib_value.to_s).to eq(default_value)
      end
    end
  end
end
