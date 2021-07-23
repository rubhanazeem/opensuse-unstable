require 'rails_helper'

RSpec.describe Webui::WebuiHelper do
  let(:input) { 'Rocking the Open Build Service' }

  describe '#elide' do
    it 'does not elide' do
      expect(input).to eq(elide(input, input.length))
    end

    it 'does elide 20 character by default in the middle' do
      expect(elide(input)).to eq('Rocking t... Service')
    end

    it 'does elide from the left' do
      expect(elide(input, 25, :left)).to eq('...the Open Build Service')
    end

    it 'does elide from the right' do
      expect(elide(input, 4, :right)).to eq('R...')
    end

    it 'returns three dots for eliding two characters' do
      expect(elide(input, 2, :right)).to eq('...')
    end

    it 'returns three dots for eliding three characters' do
      expect(elide(input, 3, :right)).to eq('...')
    end

    it 'reduces a string to 10 characters and elides in the middle by default' do
      expect(elide(input, 10)).to eq('Rock...ice')
    end
  end

  describe '#elide_two' do
    it 'elides two strings with the proper overall length' do
      input2 = "don't shorten"
      expect([input2, 'Rocking the ...uild Service']).to eq(elide_two(input2, input, 40))
    end
  end

  describe '#word_break' do
    it 'continuously adds tag after N characters' do
      expect(word_break('0123456789012345678901234567890123456789', 10)).to \
        eq('0123456789<wbr>0123456789<wbr>0123456789<wbr>0123456789')
    end

    it 'adds no tag if string is shorter than N characters' do
      expect(word_break('0123456789', 10)).to eq('0123456789')
    end

    it 'adds one tag if string is longer than N characters' do
      expect(word_break('01234567890', 10)).to eq('0123456789<wbr>0')
    end

    it 'does not evaluate HTML tags' do
      expect(word_break('01234<b>567</b>890', 3)).to eq('012<wbr>34&lt;<wbr>b&gt;5<wbr>67&lt;<wbr>/b&gt;<wbr>890')
    end

    it 'returns blank if no string given' do
      expect(word_break(nil, 3)).to eq('')
    end
  end

  describe '#bugzilla_url' do
    before do
      @configuration = { 'bugzilla_url' => 'https://bugzilla.example.org' }
      @expected_attributes = {
        classification: 7340,
        product: 'openSUSE.org',
        component: '3rd%20party%20software',
        assigned_to: '',
        short_desc: ''
      }
    end

    it 'returns link to a prefilled bugzilla enter bug form' do
      expected_url = 'https://bugzilla.example.org/enter_bug.cgi?' +
                     @expected_attributes.map { |key, value| "#{key}=#{value}" }.join('&')
      expect(bugzilla_url).to eq(expected_url)
    end

    it 'adds an assignee and description if parameters where given' do
      expected_attributes = @expected_attributes.clone
      expected_attributes[:short_desc] = 'some_description'
      expected_attributes[:assigned_to] = 'assignee@example.org'

      expected_url = 'https://bugzilla.example.org/enter_bug.cgi?' +
                     expected_attributes.map { |key, value| "#{key}=#{value}" }.join('&')
      expect(bugzilla_url(['assignee@example.org'], 'some_description')).to eq(expected_url)
    end
  end

  describe '#format_projectname' do
    it "shortens project pathes by replacing home projects with '~'" do
      expect(format_projectname('home:bob', 'bob')).to eq('~')
      expect(format_projectname('home:alice', 'bob')).to eq('~alice')
      expect(format_projectname('home:bob:foo', 'bob')).to eq('~:foo')
      expect(format_projectname('home:alice:foo', 'bob')).to eq('~alice:foo')
    end

    it 'leaves projects that are no home projects untouched' do
      expect(format_projectname('some:project:foo:bar', 'bob')).to eq('some:project:foo:bar')
    end
  end

  describe '#next_codemirror_uid' do
    before do
      @codemirror_editor_setup = 0
    end

    after do
      @codemirror_editor_setup = 0
    end

    it { expect(next_codemirror_uid).to be_instance_of(Integer) }

    context "if next_codemirror_uid get's called the first time" do
      it { expect(next_codemirror_uid).to eq(1) }
    end

    context 'if next_codemirror_uid has been called before' do
      before do
        next_codemirror_uid
      end

      it 'increases @codemirror_editor_setup by 1' do
        expect(next_codemirror_uid).to eq(2)
        expect(next_codemirror_uid).to eq(3)
      end
    end
  end

  describe '#project_or_package_link' do
    skip('Please add some tests')
  end

  describe '#creator_intentions' do
    it 'do not show the requester if they are the same as the creator' do
      expect(creator_intentions(nil)).to eq('become bugowner (previous bugowners will be deleted)')
    end

    it 'show the requester if they are different from the creator' do
      expect(creator_intentions('bugowner')).to eq('get the role bugowner')
    end
  end

  describe '#codemirror_style' do
    context 'option height' do
      it 'uses auto as default value' do
        expect(codemirror_style).not_to include('height')
      end

      it 'get set properly' do
        expect(codemirror_style(height: '250px')).to include('height: 250px;')
      end
    end

    context 'option width' do
      it 'uses auto as default value' do
        expect(codemirror_style).not_to include('width')
      end

      it 'get set properly' do
        expect(codemirror_style(width: '250px')).to include('width: 250px;')
      end
    end

    context 'option border' do
      it 'does not remove border' do
        expect(codemirror_style).not_to include('border-width')
      end

      it 'removes the border if in read-only mode' do
        expect(codemirror_style(read_only: true)).to include('border-width')
      end

      it 'removes the border if no_border is set' do
        expect(codemirror_style(no_border: true)).to include('border-width')
      end
    end
  end

  describe '#package_link' do
    skip('Please add some tests')
  end

  describe '#replace_jquery_meta_characters' do
    context 'with meta character in string' do
      it { expect(replace_jquery_meta_characters('openSUSE_Leap_42.2')).to eq('openSUSE_Leap_42_2') }
      it { expect(replace_jquery_meta_characters('openSUSE.Leap.42.2')).to eq('openSUSE_Leap_42_2') }
      it { expect(replace_jquery_meta_characters('openSUSE_Leap_42\2')).to eq('openSUSE_Leap_42_2') }
      it { expect(replace_jquery_meta_characters('openSUSE_Leap_42/2')).to eq('openSUSE_Leap_42_2') }
    end

    context 'without meta character in string' do
      it { expect(replace_jquery_meta_characters('openSUSE_Tumbleweed')).to eq('openSUSE_Tumbleweed') }
    end
  end

  describe '#pick_max_problems' do
    let(:max_shown) { 5 }

    subject { pick_max_problems(checks, builds, max_shown) }

    context 'with no failed checks' do
      let(:checks) { [] }

      context 'with no fails' do
        let(:builds) { [] }

        it { is_expected.to eq([[], [], [], []]) }
      end

      context 'with 7 fails' do
        let(:builds) { [1, 2, 3, 4, 5, 6, 7] }

        it { is_expected.to eq([[], [1, 2, 3, 4, 5], [], [6, 7]]) }
      end
    end

    context 'with 7 checks' do
      let(:checks) { [1, 2, 3, 4, 5, 6, 7] }

      context 'with no fails' do
        let(:builds) { [] }

        it { is_expected.to eq([[1, 2, 3, 4, 5], [], [6, 7], []]) }
      end

      context 'with 7 fails' do
        let(:builds) { [1, 2, 3, 4, 5, 6, 7] }

        it { is_expected.to eq([[1, 2, 3, 4], [1], [5, 6, 7], [2, 3, 4, 5, 6, 7]]) }
      end
    end
  end
end
