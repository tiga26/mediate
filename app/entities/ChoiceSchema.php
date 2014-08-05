<?php

use Kalnoy\Cruddy\Schema\BaseSchema;
use Kalnoy\Cruddy\Service\Validation\FluentValidator;

class ChoiceSchema extends BaseSchema {

    protected $model = 'Choice';

    /**
     * The name of the column that is used to convert a model to a string.
     *
     * @var string
     */
    protected $titleAttribute = null;

    /**
     * The name of the column that will sort data by default.
     *
     * @var string
     */
    protected $defaultOrder = null;

    /**
     * Define some fields.
     *
     * @param $schema
     */
    public function fields($schema)
    {
        $schema->increments('id');
        
        $schema->string('choice_name');

        $schema->integer('choice');
    }

    /**
     * Define some columns.
     *
     * @param $schema
     */
    public function columns($schema)
    {
        $schema->col('id');

        $schema->col('choice_name');

        $schema->col('choice');
    }

    /**
     * Define some files to upload.
     *
     * @param $repo
     */
    public function files($repo)
    {

    }

    /**
     * Define validation rules.
     *
     * @param $v
     */
    public function rules($v)
    {
        $v->rules(
        [

        ]);
    }
}