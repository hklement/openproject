#-- encoding: UTF-8
#-- copyright
# OpenProject is a project management system.
# Copyright (C) 2012-2015 the OpenProject Foundation (OPF)
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
# Copyright (C) 2006-2013 Jean-Philippe Lang
# Copyright (C) 2010-2013 the ChiliProject Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# See doc/COPYRIGHT.rdoc for more details.
#++
require 'spec_helper'
require 'ostruct'

TestViewHelper = Class.new(ActionView::Base)

describe TabularFormBuilder do
  include Capybara::RSpecMatchers

  let(:helper)   { TestViewHelper.new }
  let(:resource) { FactoryGirl.build(:user) }
  let(:builder)  { TabularFormBuilder.new(:user, resource, helper, {}, nil) }

  shared_examples_for 'labelled by default' do
    context 'by default' do
      it { is_expected.to have_selector 'label' }
    end

    context 'with no_label option' do
      let(:options) { { no_label: true } }

      it { is_expected.not_to have_selector 'label' }
    end
  end

  describe '#text_field' do
    let(:options) { { title: 'Name' } }

    subject(:output) {
      builder.text_field :name, options
    }

    it_behaves_like 'labelled by default'

    it 'should output element' do
      expect(output).to have_selector 'input[type="text"]'
    end
  end

  describe '#select' do
    let(:options) { { title: 'Name' } }

    subject(:output) {
      builder.select :name, '<option value="33">FUN</option>'.html_safe, options
    }

    it_behaves_like 'labelled by default'

    it 'should output element' do
      expect(output).to have_selector 'select'
      expect(output).to have_selector 'option[value="33"]'
      expect(output).to have_text 'FUN'
    end
  end

  describe '#collection_select' do
    let(:options) { { title: 'Name' } }

    subject(:output) {
      builder.collection_select :name, [
        OpenStruct.new(id: 56, name: 'Diana'),
        OpenStruct.new(id: 46, name: 'Ricky'),
        OpenStruct.new(id: 33, name: 'Jonas')
      ], :id, :name, options
    }

    it_behaves_like 'labelled by default'

    it 'should output element' do
      expect(output).to have_selector 'select > option', count: 3
      expect(output).to have_selector 'option:first[value="56"]'
      expect(output).to have_text 'Jonas'
    end
  end

  describe '#date_select' do
    let(:options) { { title: 'Name' } }

    subject(:output) {
      builder.date_select :created_on, options
    }

    it_behaves_like 'labelled by default'

    it 'should output element' do
      expect(output).to have_selector 'select', count: 3
      expect(output).to have_selector 'select:nth-of-type(2) > option', count: 12
      expect(output).to have_selector 'select:last > option', count: 31
    end
  end

  # misc.

  %w(check_box email_field number_field password_field).each do |meth|
    describe "##{meth}" do
      let(:options) { { title: 'Name' } }

      subject(:output) {
        builder.send(meth, :name, options)
      }

      it_behaves_like 'labelled by default'
    end
  end
end
