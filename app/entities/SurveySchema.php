<?php

use Kalnoy\Cruddy\Schema\BaseSchema;
use Kalnoy\Cruddy\Service\Validation\FluentValidator;

class SurveySchema extends BaseSchema {

    protected $model = 'Survey';

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
        
        $schema->string('mood_question');

        $schema->string('mood_resource_id');
    }

    /**
     * Define some columns.
     *
     * @param $schema
     */
    public function columns($schema)
    {
        $schema->col('id');

        $schema->col('mood_question');
        
        $schema->col('mood_resource_id');
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